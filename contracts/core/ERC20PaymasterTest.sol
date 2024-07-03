// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;


import "./BasePaymaster.sol";
import "../interfaces/IEntryPoint.sol";



contract ERC20PaymasterTest is BasePaymaster {

    event GasEstimates(uint256 actualGasCost);
    constructor(IEntryPoint _entrypoint) BasePaymaster(_entrypoint) Ownable(msg.sender) {}

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    internal override pure returns (bytes memory context, uint256 validationData) {
        context=bytes("0x");
        validationData=0;
    }

    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        emit GasEstimates(actualGasCost);
    }
}