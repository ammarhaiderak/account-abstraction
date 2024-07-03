pragma solidity ^0.8.23;





contract MyTC {

     struct UserOperation {

        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
    }

    bytes4 private constant approveSig = bytes4(0x095ea7b3);

    //0xb61d27f6000000000000000000000000a859d441e35aecfb05ff7aad07845beca3f15b14
    // 000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044
    // 095ea7b3000000000000000000000000618a3aaebf6310dae767c67cbd9240b42efdb11d000000000000000000000000000000000000000000084595161401484a00000000000000000000000000000000000000000000000000000000000000

    // 0xb61d27f6000000000000000000000000a859d441e35aecfb05ff7aad07845beca3f15b14000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044
    

    //expected: 0x095ea7b30000000000000000000000003516c191f331211316050b81807532cf691009200000000000000000000000000000000000000000000000000000000005f5e100
    //actual: 0x095ea7b30000000000000000000000003516c191f331211316050b81807532cf691009200000000000000000000000000000000000000000000000000000000005f5e100
            //   0x095ea7b3000000000000000000000000a2d2db59a5868490e850385d766c6e8be94682df000000000000000000000000000000000000000000084595161401484a00000000000000000000000000000000000000000000000000000000000000  
    // keccak256: 0x095ea7b334ae44009aa867bfb386f5c3b4b443ac6f0ee573fa91c4608fbadfba
    function myEnc() public view returns (bytes memory, bytes32, bytes4, bool) {
        bytes memory cd = abi.encodeWithSignature("approve(address,uint256)", 0x3516c191F331211316050B81807532CF69100920, 100000000);
        bytes32 kc = bytes32(keccak256("approve(address,uint256)"));
        bytes4 sig = bytes4(cd);
        bool res = bytes4(0x095ea7b3) == sig;
        return (cd,kc, sig, res);
    }

    // function myDec(bytes calldata encodedAll, uint8 start, uint8 end) public view returns (bytes memory) {
    //     return encodedAll[start:end];
    // }

     function _validatePaymasterUserOp(UserOperation calldata userOp, uint256 maxCost)
        external
        view
        returns (uint8 mode, bytes4 _funcSelec, address _rec)
    {
        address sender = userOp.sender;
        // if(!whitelisted[userOp.sender]) {
        //     revert NotWhitelisted();
        // }

        // uint192 tokenPrice = getPrice();
       
        // uint256 maxTokenNeeded = ((maxCost + usdtSponsored[sender]) * priceMarkup * tokenPrice) / (1e18 * PRICE_DENOMINATOR);
        // uint256 allowance = token.allowance(sender, address(this));

        mode = 0; // 0 = normal transaction that is charged in usdt, 1 = approval transaction for USDt we certainly cant take USDt as there will be no allowance.
        bytes4 funcSelector = bytes4(userOp.callData[132:]);
        address receiver = address(bytes20(userOp.callData[16:36]));
        
        
        if(funcSelector == approveSig && receiver == 0xA859D441e35AecFb05Ff7aad07845becA3f15b14) {
            mode = 1;
            
            // if (allowance >= maxTokenNeeded) {
            //     revert AlreadyEnoughAllowance();
            // }
        }

        // if(mode == 0 && allowance < maxTokenNeeded) {
        //     revert NotEnoughAllowance();
        // }

        // context = abi.encodePacked(mode, tokenPrice, userOp.sender, userOpHash);

        _funcSelec = funcSelector;
        _rec = receiver;
    }
      
}