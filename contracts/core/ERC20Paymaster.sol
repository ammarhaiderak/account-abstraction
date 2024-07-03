// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import "./BasePaymaster.sol";
import "../interfaces/IEntryPoint.sol";

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";


/// @title ERC20Paymaster
/// @author Pimlico (https://github.com/pimlicolabs/erc20-paymaster/blob/main/src/ERC20Paymaster.sol)
/// @author Using Solady (https://github.com/vectorized/solady)
/// @notice An ERC-4337 Paymaster contract which is able to sponsor gas fees in exchange for ERC-20 tokens.
/// The contract refunds excess tokens. It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses oracles to fetch the latest token prices.
/// The paymaster supports standard and up-rebasing ERC-20 tokens. It does not support down-rebasing and fee-on-transfer tokens.
/// @dev Inherits from BasePaymaster.
/// @custom:security-contact security@pimlico.io
contract ERC20Paymaster is BasePaymaster {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    /// @dev The token amount is higher than the limit set.
    error NotEnoughAllowance();

    /// @dev The token limit is set to zero in a paymaster mode that uses a limit.
    error AlreadyEnoughAllowance();

    /// @dev The price markup selected is higher than the price markup limit.
    error PriceMarkupTooHigh();

    /// @dev The price markup selected is lower than break-even.
    error PriceMarkupTooLow();

    /// @dev The oracle price is stale.
    error OraclePriceStale();

    /// @dev The oracle price is less than or equal to zero.
    error OraclePriceNotPositive();

    /// @dev The oracle decimals are not set to 8.
    error OracleDecimalsInvalid();

    /// @dev The sender is not whitelisted.
    error NotWhitelisted();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when the price markup is updated.
    event MarkupUpdated(uint32 priceMarkup);

    /// @dev Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        address indexed user,
        address indexed guarantor,
        uint256 tokenAmountPaid,
        uint256 tokenPrice,
        bool paidByGuarantor
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The precision used for token price calculations.
    uint256 public constant PRICE_DENOMINATOR = 1e6;

    /// @dev The ERC20 token used for transaction fee payments.
    IERC20 public immutable token;

    /// @dev The number of decimals used by the ERC20 token.
    uint256 public immutable tokenDecimals;

    /// @dev The oracle contract used to fetch the latest ERC20 to USD token prices.
    IOracle public immutable tokenOracle;

    /// @dev The Oracle contract used to fetch the latest native asset (e.g. ETH) to USD prices.
    IOracle public immutable nativeAssetOracle;

    // @dev The amount of time in seconds after which an oracle result should be considered stale.
    uint32 public immutable stalenessThreshold;

    /// @dev The maximum price markup percentage allowed (1e6 = 100%).
    uint32 public immutable priceMarkupLimit;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The price markup percentage applied to the token price (1e6 = 100%).
    uint32 public priceMarkup;

    bytes4 private constant approveSig = bytes4(0x095ea7b3);

    mapping(address=>bool) public whitelisted;

    mapping(address=>uint256) public usdtSponsored;



    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the ERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The ERC-4337 EntryPoint contract.
    /// @param _tokenOracle The oracle contract used to fetch the latest token prices.
    /// @param _nativeAssetOracle The oracle contract used to fetch the latest native asset (ETH, Matic, Avax, etc.) prices.
    /// @param _owner The address that will be set as the owner of the contract.
    /// @param _priceMarkupLimit The maximum price markup percentage allowed (1e6 = 100%).
    /// @param _priceMarkup The initial price markup percentage applied to the token price (1e6 = 100%).
    constructor(
        IERC20Metadata _token, //sepolia: 0xEa0639a4b18f6C59a8544d6ea81eB85e2312F07F - base-sepolia: 0xA859D441e35AecFb05Ff7aad07845becA3f15b14
        IEntryPoint _entryPoint, //0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint32 _stalenessThreshold,
        address _owner,
        uint32 _priceMarkupLimit,
        uint32 _priceMarkup
    ) BasePaymaster(_entryPoint) Ownable(_owner) {
        token = _token;
        tokenOracle = _tokenOracle; // oracle for token -> usd //sepolia: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E -> base-sepolia: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        nativeAssetOracle = _nativeAssetOracle; // oracle for native asset(eth/matic/avax..) -> usd //sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306 // base-sepoloa: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1
        stalenessThreshold = _stalenessThreshold; //172800 -> 48 hours 
        priceMarkupLimit = _priceMarkupLimit; //1200000
        priceMarkup = _priceMarkup; //1100000
        tokenDecimals = 10 ** _token.decimals();
        if (_priceMarkup < 1e6) {
            revert PriceMarkupTooLow();
        }
        if (_priceMarkup > _priceMarkupLimit) {
            revert PriceMarkupTooHigh();
        }
        if (_tokenOracle.decimals() != 8 || _nativeAssetOracle.decimals() != 8) {
            revert OracleDecimalsInvalid();
        }
    }


    function setWhitelist(address[] memory sender, bool[] memory status) external onlyOwner {
        uint8 slen = uint8(sender.length);
        uint8 stlen = uint8(status.length);
        require(slen == stlen, "length mismatched !");
        for(uint8 i=0; i < slen; i++) {
            whitelisted[sender[i]]=status[i];
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-4337 PAYMASTER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates the paymaster data, calculates the required token amount, and transfers the tokens.
    /// @dev The paymaster supports one of four modes:
    /// 0. user pays, no limit
    ///     empty bytes (or any bytes with the first byte = 0x00)
    /// 1. user pays, with a limit
    ///     hex"01" + token spend limit (32 bytes)
    /// @param userOp The user operation.
    /// @param userOpHash The hash of the user operation.
    /// @param maxCost The maximum cost in native tokens of this user operation.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        override
        returns (bytes memory context, uint256 validationResult)
    {
        address sender = userOp.sender;
        if(!whitelisted[userOp.sender]) {
            revert NotWhitelisted();
        }

        uint192 tokenPrice = getPrice();
       
        uint256 maxTokenNeeded = ((maxCost + usdtSponsored[sender]) * priceMarkup * tokenPrice) / (1e18 * PRICE_DENOMINATOR);
        uint256 allowance = token.allowance(sender, address(this));

        uint8 mode = 0; // 0 = normal transaction that is charged in usdt, 1 = approval transaction for USDt we certainly cant take USDt as there will be no allowance.
        bytes4 funcSelector = bytes4(userOp.callData[132:]);
        address receiver = address(bytes20(userOp.callData[16:36]));
        
        
        if(funcSelector == approveSig && receiver == address(token)) {
            mode = 1;
            
            if (allowance >= maxTokenNeeded) {
                revert AlreadyEnoughAllowance();
            }
        }

        if(mode == 0 && allowance < maxTokenNeeded) {
            revert NotEnoughAllowance();
        }

        context = abi.encodePacked(mode, tokenPrice, userOp.sender, userOpHash);
        validationResult = 0;
    }

    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost)
        internal
        override
    {
        uint8 mode = uint8(bytes1(context[0:1]));
        uint192 tokenPrice = uint192(bytes24(context[1:25]));
        address sender = address(bytes20(context[25:45]));
        bytes32 userOpHash = bytes32(context[45:77]);

        if(mode == 1) {
            // sponsor approve transaction without USDt deduction & record it
            usdtSponsored[sender] += actualGasCost;
            emit UserOperationSponsored(userOpHash, sender, address(0), 0, tokenPrice, false);
        } else {
            uint256 actualTokenNeeded = ((actualGasCost + usdtSponsored[sender]) * priceMarkup * tokenPrice) / (1e18 * PRICE_DENOMINATOR);
            SafeTransferLib.safeTransferFrom(address(token), sender, address(this), actualTokenNeeded);
            usdtSponsored[sender] = 0; // resetting usdt sponsor for approve as we have deducted that.

            emit UserOperationSponsored(userOpHash, sender, address(0), actualTokenNeeded, tokenPrice, false);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the price markup.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    function updateMarkup(uint32 _priceMarkup) external onlyOwner {
        if (_priceMarkup < 1e6) {
            revert PriceMarkupTooLow();
        }
        if (_priceMarkup > priceMarkupLimit) {
            revert PriceMarkupTooHigh();
        }
        priceMarkup = _priceMarkup;
        emit MarkupUpdated(_priceMarkup);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(address(token), to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC HELPERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Fetches the latest token price.
    /// @return price The latest token price fetched from the oracles.
    function getPrice() public view returns (uint192) {
        uint192 tokenPrice = _fetchPrice(tokenOracle);
        uint192 nativeAssetPrice = _fetchPrice(nativeAssetOracle);
        uint192 price = nativeAssetPrice * uint192(tokenDecimals) / tokenPrice;

        return price;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Parses the paymasterAndData field of the user operation and returns the paymaster mode and data.
    /// @param _paymasterAndData The paymasterAndData field of the user operation.
    /// @return mode The paymaster mode.
    /// @return paymasterConfig The paymaster configuration data.
    function _parsePaymasterAndData(bytes calldata _paymasterAndData) internal pure returns (uint8, bytes calldata) {
        if (_paymasterAndData.length < 53) {
            return (0, msg.data[0:0]);
        }
        return (uint8(_paymasterAndData[52]), _paymasterAndData[53:]);
    }

    /// @notice Fetches the latest price from the given oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetOracle.
    /// @param _oracle The oracle contract to fetch the price from.
    /// @return price The latest price fetched from the oracle.
    function _fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (, int256 answer,, uint256 updatedAt,) = _oracle.latestRoundData();
        if (answer <= 0) {
            revert OraclePriceNotPositive();
        }
        if (updatedAt < block.timestamp - stalenessThreshold) {
            revert OraclePriceStale();
        }
        price = uint192(int192(answer));
    }
}
