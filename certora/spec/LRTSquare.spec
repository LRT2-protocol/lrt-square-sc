// use builtin rule sanity;

methods {
    function balanceOf(address account) external returns (uint256) envfree; 
    function previewDeposit(address[] memory _tokens, uint256[] memory _amounts) external returns (uint256, uint256); 
    function paused() external returns (bool) envfree;
}

rule Deposit(env e, address[] tokens, uint256[] amounts, address receiver) {
    require amounts[0] != 0;
    uint256 shareToMint;
    uint256 feeForDeposit;
    (shareToMint, feeForDeposit) = currentContract.previewDeposit(e, tokens, amounts);

    require to_mathint(shareToMint) > 0;
    
    uint256 balBefore = currentContract.balanceOf(receiver);
    deposit(e, tokens, amounts, receiver);
    uint256 balAfter = currentContract.balanceOf(receiver);

    assert balAfter == balBefore + shareToMint;
}

// Verified
rule Redeem (env e, uint256 vaultShares) {
    require vaultShares != 0;
    require currentContract.fee.treasury != e.msg.sender;

    uint256 balBefore = currentContract.balanceOf(e.msg.sender);
    redeem(e, vaultShares);
    uint256 balAfter = currentContract.balanceOf(e.msg.sender);

    assert balBefore - balAfter == vaultShares; 
}

// Verified
rule CannotDepositWhenPaused (env e, address[] tokens, uint256[] amounts, address receiver) {
    bool isPaused = currentContract.paused();
    require isPaused == true;

    deposit@withrevert(e, tokens, amounts, receiver);
    bool isReverted = lastReverted;

    assert isReverted == true;
}

// Verified
rule CanRedeemWhenPaused (env e, uint256 vaultShares) {
    bool isPaused = currentContract.paused();
    require isPaused == true;
    require vaultShares != 0;
    require currentContract.fee.treasury != e.msg.sender;

    uint256 balBefore = currentContract.balanceOf(e.msg.sender);
    redeem(e, vaultShares);
    uint256 balAfter = currentContract.balanceOf(e.msg.sender);

    assert balBefore - balAfter == vaultShares; 
}