//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/MetaVesT.sol";
import "src/MetaVesTController.sol";

/// @dev foundry framework testing of MetaVesT.sol including mock tokens
/// NOTE: many MetaVesT functions are permissioned and conditions are housed in MetaVesTController that are assumed in here; see
/// MetaVesTController.t.sol for such tests

interface IGetTransferees {
    function transferees(address grantee, uint256 index) external view returns (address);
}

abstract contract ERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

contract TestToken is ERC20 {
    string public constant TESTTOKEN_NAME = "Test Token";
    string public constant TESTTOKEN_SYMBOL = "TEST";
    uint8 public constant TESTTOKEN_DECIMALS = 18;

    constructor() ERC20(TESTTOKEN_NAME, TESTTOKEN_SYMBOL, TESTTOKEN_DECIMALS) {}

    //allow anyone to mint the token for testing
    function mintToken(address to, uint256 amt) public {
        _mint(to, amt);
    }
}

contract TestToken2 is ERC20 {
    string public constant TESTTOKEN_NAME = "Test Token 2";
    string public constant TESTTOKEN_SYMBOL = "TEST2";
    uint8 public constant TESTTOKEN_DECIMALS = 6; //test different decimals amount

    constructor() ERC20(TESTTOKEN_NAME, TESTTOKEN_SYMBOL, TESTTOKEN_DECIMALS) {}

    //allow anyone to mint the token for testing
    function mintToken(address to, uint256 amt) public {
        _mint(to, amt);
    }
}

/// @notice test contract for MetaVesT.sol using Foundry
contract MetaVesTTest is Test {
    address internal constant AUTHORITY = address(333);
    address internal constant DAO = address(444);

    uint48 internal _timestamp;

    TestToken internal testToken;
    TestToken2 internal testToken2;
    MetaVesT internal metavestTest;
    MetaVesTController internal controller;
    IMetaVesT internal imetavest;

    MetaVesT.Milestone[] internal emptyMilestones;

    bool internal baseCondition;

    address metavestTestAddr;
    address controllerAddr;
    address testTokenAddr;
    address testToken2Addr;
    address testPaymentToken;

    function setUp() public {
        testToken = new TestToken();
        testToken2 = new TestToken2();
        testTokenAddr = address(testToken);
        testToken2Addr = address(testToken2);
        testPaymentToken = address(testToken2);
        controller = new MetaVesTController(AUTHORITY, DAO, testPaymentToken);
        controllerAddr = address(controller);

        metavestTest = new MetaVesT(AUTHORITY, controllerAddr, testPaymentToken);
        metavestTestAddr = address(metavestTest);
        imetavest = IMetaVesT(metavestTestAddr);
    }

    function testConstructor() public {
        assertEq(metavestTest.controller(), controllerAddr, "controller did not initialize");
        assertEq(metavestTest.authority(), AUTHORITY, "authority did not initialize");
        assertEq(metavestTest.paymentToken(), testPaymentToken, "paymentToken did not initialize");
    }

    function testCreateMetavest(address _grantee, uint256 _total, bool _transferable) external {
        vm.assume(_total > 1000 && _grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _total,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: 0,
                unlockingCliffCredit: 0,
                vestingRate: uint160(10),
                vestingStartTime: uint48(2 ** 20),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(2 ** 20),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: testTokenAddr
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: true}),
            milestones: emptyMilestones, // milestones tested separately
            grantee: _grantee,
            transferable: _transferable
        });

        testToken.mintToken(AUTHORITY, _total);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, _total);

        vm.startPrank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, _total);

        MetaVesT.MetaVesTDetails memory _newDetails = metavestTest.getMetavestDetails(_metavestDetails.grantee);
        assertEq(_total, testToken.balanceOf(metavestTestAddr));
        assertEq(_metavestDetails.grantee, _newDetails.grantee, "metavestDetails not stored");
        assertEq(
            metavestTest.nonwithdrawableAmount(_metavestDetails.grantee),
            _total,
            "nonwithdrawableAmount did not update"
        );
    }

    function testUpdateTransferability(address _grantee, bool _isTransferable) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateTransferability(_grantee, _isTransferable);

        assertTrue(
            metavestTest.getMetavestDetails(_grantee).transferable == _isTransferable,
            "transferability did not update"
        );
    }

    function testUpdateUnlockRate(address _grantee, uint160 _unlockRate) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateUnlockRate(_grantee, _unlockRate);
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        assertEq(_details.allocation.unlockRate, _unlockRate, "unlockRate did not update");
    }

    function testUpdateVestingRate(address _grantee, uint160 _vestingRate) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateVestingRate(_grantee, _vestingRate);
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        assertEq(_details.allocation.vestingRate, _vestingRate, "vestingRate did not update");
    }

    function testUpdateStopTimes(
        address _grantee,
        uint48 _unlockStopTime,
        uint48 _vestingStopTime,
        uint48 _shortStopTime
    ) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateStopTimes(_grantee, _unlockStopTime, _vestingStopTime, _shortStopTime);
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        MetaVesT.MetaVesTType _type = _details.metavestType;

        if (
            _type == MetaVesT.MetaVesTType.OPTION &&
            _details.option.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(_details.option.shortStopTime, _shortStopTime, "option shortStopTime did not update");
        } else if (
            _type == MetaVesT.MetaVesTType.RESTRICTED &&
            _details.rta.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(_details.rta.shortStopTime, _shortStopTime, "rta shortStopTime did not update");
        }
        assertEq(_details.allocation.unlockStopTime, _unlockStopTime, "unlockStopTime did not update");
        assertEq(_details.allocation.vestingStopTime, _vestingStopTime, "vestingStopTime did not update");
    }

    function testConfirmMilestone(address _grantee, uint8 _milestoneIndex) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, true);
        uint256 _beforeVested = _details.allocation.tokensVested;
        block.number / 2 == 0 ? baseCondition = true : baseCondition = false;

        bool _result;
        if (_milestoneIndex < _details.milestones.length)
            _result = IConditionM(_details.milestones[_milestoneIndex].conditionContracts[0]).checkCondition();

        if (_milestoneIndex >= _details.milestones.length || _details.milestones[_milestoneIndex].complete || !_result)
            vm.expectRevert();
        metavestTest.confirmMilestone(_grantee, _milestoneIndex);

        if (_result) {
            assertTrue(
                metavestTest.getMetavestDetails(_grantee).milestones[_milestoneIndex].complete,
                "not marked complete"
            );
            assertEq(
                metavestTest.getMetavestDetails(_grantee).milestones[_milestoneIndex].milestoneAward,
                0,
                "milestoneAward not deleted"
            );
            assertGt(
                metavestTest.getMetavestDetails(_grantee).allocation.tokensVested,
                _beforeVested,
                "vested amount did not increase"
            );
        }
    }

    function testRemoveMilestone(address _grantee, uint8 _milestoneIndex) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, true);
        uint256 _beforenonwithdrawableAmount = metavestTest.nonwithdrawableAmount(_grantee);
        vm.startPrank(controllerAddr);
        bool _reverted;
        if (_milestoneIndex >= _details.milestones.length) {
            _reverted = true;
            vm.expectRevert();
        }
        metavestTest.removeMilestone(_milestoneIndex, _grantee, _details.allocation.tokenContract);
        if (!_reverted) {
            assertEq(
                metavestTest.getMetavestDetails(_grantee).milestones[_milestoneIndex].milestoneAward,
                0,
                "milestoneAward was not deleted"
            );
            assertGt(
                _beforenonwithdrawableAmount,
                metavestTest.nonwithdrawableAmount(_grantee),
                "nonwithdrawableAmount not reduced"
            );
        }
    }

    // note the conditional ensuring the tokens comprising milestoneAward are transferred (and that milestoneAward > 0) is in MetaVesTController and not tested here
    function testAddMilestone(address _grantee, MetaVesT.Milestone calldata _milestone) external {
        vm.assume(_grantee != address(0) && _milestone.milestoneAward > 0 && _milestone.milestoneAward < 1e30);
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, true);
        vm.prank(address(3));
        vm.expectRevert();
        metavestTest.addMilestone(_grantee, _milestone);
        uint256 _beforeLocked = metavestTest.nonwithdrawableAmount(_grantee);
        uint256 _beforeLength = _details.milestones.length;
        vm.startPrank(controllerAddr);
        metavestTest.addMilestone(_grantee, _milestone);
        assertGt(
            metavestTest.getMetavestDetails(_grantee).milestones.length,
            _beforeLength,
            "milestones array did not increment length"
        );
        assertGt(metavestTest.nonwithdrawableAmount(_grantee), _beforeLocked, "nonwithdrawableAmount did not increase");
    }

    function testUpdatePrice(address _grantee, uint128 _newPrice) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        MetaVesT.MetaVesTType _type = _details.metavestType;
        if (_type == MetaVesT.MetaVesTType.ALLOCATION) vm.expectRevert();
        metavestTest.updatePrice(_grantee, _newPrice);

        if (_type == MetaVesT.MetaVesTType.OPTION) {
            assertEq(
                metavestTest.getMetavestDetails(_grantee).option.exercisePrice,
                _newPrice,
                "option exercise price did not update"
            );
        } else if (_type == MetaVesT.MetaVesTType.RESTRICTED) {
            assertEq(
                metavestTest.getMetavestDetails(_grantee).rta.repurchasePrice,
                _newPrice,
                "rta repurchase price did not update"
            );
        }
    }

    function testTerminateVesting(address _grantee) external {
        vm.assume(_grantee != address(0));
        _createBasicMilestoneMetavest(_grantee, true);
        uint256 _beforeBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _beforeAuthorityBalance = testToken.balanceOf(AUTHORITY);
        uint256 _beforeNonWithdrawable = metavestTest.nonwithdrawableAmount(_grantee);

        vm.expectRevert();
        metavestTest.terminateVesting(_grantee);
        vm.prank(controllerAddr);
        metavestTest.terminateVesting(_grantee);

        assertTrue(_beforeBalance >= testToken.balanceOf(metavestTestAddr), "metavest balance not properly changed");
        assertTrue(
            _beforeNonWithdrawable >= metavestTest.nonwithdrawableAmount(_grantee),
            "grantee's balance not properly changed"
        );
        assertTrue(
            _beforeAuthorityBalance <= testToken.balanceOf(AUTHORITY),
            "authority's balance not properly changed"
        );
        assertEq(
            0,
            metavestTest.getMetavestDetails(_grantee).allocation.vestingRate,
            "grantee's vestingRate not deleted"
        );
        assertEq(
            0,
            metavestTest.getMetavestDetails(_grantee).allocation.vestingCliffCredit,
            "grantee's vestingCliffCredit not deleted"
        );
    }

    function testTerminate(address _grantee) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, true);
        uint256 _beforeBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _beforeGranteeBalance = testToken.balanceOf(_grantee);
        uint256 _beforeAuthorityBalance = testToken.balanceOf(AUTHORITY);
        uint256 _beforeLocked = metavestTest.nonwithdrawableAmount(_grantee);
        uint256 _beforeWithdrawable = metavestTest.getAmountWithdrawable(_grantee, _details.allocation.tokenContract);
        uint256 _remainder = _beforeLocked -
            _details.allocation.tokensVested -
            _details.allocation.vestedTokensWithdrawn;
        if (_details.metavestType != MetaVesT.MetaVesTType.OPTION)
            _beforeWithdrawable += _details.allocation.tokensVested;
        else _remainder += _details.allocation.tokensVested;

        vm.expectRevert();
        metavestTest.terminate(_grantee);
        vm.prank(controllerAddr);
        metavestTest.terminate(_grantee);

        assertGt(_beforeBalance, testToken.balanceOf(metavestTestAddr), "metavest balance not properly changed");
        if (_beforeWithdrawable != 0)
            assertGt(
                _beforeGranteeBalance,
                testToken.balanceOf(_grantee),
                "grantee's balance not properly changed by withdrawable amount"
            );
        assertGt(testToken.balanceOf(AUTHORITY), _beforeAuthorityBalance, "authority's balance not properly changed");
        assertEq(
            0,
            metavestTest.getAmountWithdrawable(_grantee, testTokenAddr),
            "grantee still has withdrawable balance"
        );
        assertEq(0, metavestTest.nonwithdrawableAmount(_grantee), "nonwithdrawableAmount not deleted");
        assertEq(address(0), metavestTest.getMetavestDetails(_grantee).grantee, "grantee's metavest not deleted");
    }

    function testTransferRights(uint128 _divisor, address _transferee, address _grantee, bool _transferable) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, _transferable);
        uint256 _beforeNonwithdrawable = metavestTest.nonwithdrawableAmount(_grantee);
        uint256 _beforeTransfereenonWithdrawable = metavestTest.nonwithdrawableAmount(_transferee);
        uint256 _beforeTotal = _details.allocation.tokenStreamTotal;
        bool _reverted;

        vm.expectRevert();
        metavestTest.transferRights(_divisor, _transferee);
        vm.startPrank(_grantee);
        if (
            _divisor == 0 ||
            _transferee == address(0) ||
            metavestTest.getMetavestDetails(_transferee).grantee != address(0) ||
            _transferee == metavestTest.authority() ||
            _transferee == metavestTest.controller() ||
            !_transferable
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        metavestTest.transferRights(_divisor, _transferee);

        // if the divisor is too high, the amounts transferred to transferee will == 0 from rounding, so adding 1 allows 'assertGt' to capture greater than or equal, which is more ideal
        if (!_reverted) {
            assertGt(
                _beforeNonwithdrawable + 1,
                metavestTest.nonwithdrawableAmount(_grantee),
                "grantee's nonwithdrawableAmount not <="
            );
            assertGt(
                metavestTest.nonwithdrawableAmount(_transferee) + 1,
                _beforeTransfereenonWithdrawable,
                "grantee's nonwithdrawableAmount <="
            );
            assertGt(
                _beforeTotal + 1,
                metavestTest.getMetavestDetails(_grantee).allocation.tokenStreamTotal,
                "total allocated tokens not <="
            );

            assertEq(
                _beforeTotal,
                metavestTest.getMetavestDetails(_grantee).allocation.tokenStreamTotal +
                    metavestTest.getMetavestDetails(_transferee).allocation.tokenStreamTotal,
                "grantee and transferee together should have the same total as grantee pre-transfer"
            );
            assertGt(metavestTest.getMetavestDetails(_transferee).milestones.length, 0, "milestones did not transfer");
            assertEq(
                IGetTransferees(metavestTestAddr).transferees(_grantee, 0),
                _transferee,
                "transferee not added to transferees array element 0"
            );
        }
    }

    function testExerciseOption(address _grantee, uint256 _amount) external {
        vm.assume(_grantee != address(0) && metavestTest.getMetavestDetails(_grantee).grantee == address(0));
        _createTokenOptionMetavest(_grantee);
        vm.warp(block.timestamp + 10); // ten seconds worth of vesting
        metavestTest.refreshMetavest(_grantee); // recalculate initiated values
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        uint256 _beforeNonwithdrawable = metavestTest.nonwithdrawableAmount(_grantee);
        uint256 _beforeWithdrawableController = metavestTest.getAmountWithdrawable(
            metavestTest.controller(),
            metavestTest.paymentToken()
        );
        bool _reverted;
        uint256 _vested = metavestTest.getMetavestDetails(_grantee).allocation.tokensVested;
        vm.startPrank(_grantee);
        if (
            _amount == 0 || _grantee != _details.grantee || _amount > _vested // we can remove the _milestoneVested and _tokensExercised check since they're internal to metavest.sol and we know they're both 0 here
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        metavestTest.exerciseOption(_amount);

        if (!_reverted) {
            assertGt(
                _beforeNonwithdrawable,
                metavestTest.nonwithdrawableAmount(_grantee),
                "nonwithdrawable amount did not decrease due to tokensExercised"
            );
            assertGt(
                metavestTest.getAmountWithdrawable(metavestTest.controller(), metavestTest.paymentToken()),
                _beforeWithdrawableController,
                "controller paymentToken amountWithdrawable did not increase"
            );
        }
    }

    function testWithdrawAllController() external {
        _createTokenOptionMetavest(address(999));
        vm.warp(block.timestamp + 10); // ten seconds worth of vesting
        metavestTest.refreshMetavest(address(999)); // recalculate initiated values
        uint256 _beforeControllerBalance = testToken2.balanceOf(metavestTest.controller());
        uint256 _beforeMetavestContractBalance = testToken.balanceOf(metavestTestAddr);
        vm.prank(address(999));
        metavestTest.exerciseOption(100);
        vm.startPrank(metavestTest.controller());
        metavestTest.withdrawAll(metavestTest.paymentToken());

        assertGt(
            testToken2.balanceOf(metavestTest.controller()),
            _beforeControllerBalance,
            "grantee's balance should have increased by amountWithdrawable"
        );
        assertGt(
            _beforeMetavestContractBalance,
            testToken2.balanceOf(metavestTestAddr),
            "tokens not withdrawn from metavest"
        );
    }

    function testWithdrawAll(address _grantee, uint256 _unlocked, uint256 _vested) external {
        vm.assume(_grantee != address(0));
        vm.assume(
            _unlocked != 0 && _vested != 0 && _unlocked < type(uint256).max / 2 && _vested < type(uint256).max / 2
        );
        _createWithdrawableMetavest(_grantee, _unlocked, _vested);
        metavestTest.refreshMetavest(_grantee); // makes the _unlocked && _vested tokens withdrawable
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        uint256 _beforeGranteeBalance = testToken.balanceOf(_grantee);
        uint256 _beforeMetavestContractBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _newlyWithdrawable = _min(_unlocked, _vested);

        vm.startPrank(_grantee);
        metavestTest.withdrawAll(testTokenAddr);

        assertEq(
            _newlyWithdrawable,
            testToken.balanceOf(_grantee) - _beforeGranteeBalance,
            "grantee's balance should have increased by amountWithdrawable"
        );
        assertGt(
            _beforeMetavestContractBalance,
            testToken.balanceOf(metavestTestAddr),
            "tokens not withdrawn from metavest"
        );
        assertEq(
            _details.allocation.tokensVested,
            metavestTest.getMetavestDetails(_grantee).allocation.tokensVested,
            "vested tracker should not have changed"
        );
        assertGt(
            metavestTest.getMetavestDetails(_grantee).allocation.vestedTokensWithdrawn,
            _details.allocation.vestedTokensWithdrawn,
            "vested tokens withdrawn should have changed"
        );
        assertEq(
            _details.allocation.tokensUnlocked,
            metavestTest.getMetavestDetails(_grantee).allocation.tokensUnlocked,
            "unlocked tracker should not have changed"
        );
        assertGt(
            metavestTest.getMetavestDetails(_grantee).allocation.unlockedTokensWithdrawn,
            _details.allocation.unlockedTokensWithdrawn,
            "unlocked tokens withdrawn should have changed"
        );
        assertEq(
            _details.allocation.tokenStreamTotal,
            metavestTest.getMetavestDetails(_grantee).allocation.tokenStreamTotal,
            "tokenStreamTotal should not have changed"
        );
    }

    function testWithdraw(address _grantee, uint256 _unlocked, uint256 _vested, uint256 _amount) external {
        vm.assume(_grantee != address(0));
        vm.assume(
            _unlocked != 0 && _vested != 0 && _unlocked < type(uint256).max / 2 && _vested < type(uint256).max / 2
        );
        _createWithdrawableMetavest(_grantee, _unlocked, _vested);
        metavestTest.refreshMetavest(_grantee); // makes the _unlocked && _vested tokens withdrawable
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        uint256 _beforeGranteeBalance = testToken.balanceOf(_grantee);
        uint256 _beforeMetavestContractBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _newlyWithdrawable = _min(_unlocked, _vested);
        bool _reverted;

        vm.startPrank(_grantee);
        if (_amount > metavestTest.getAmountWithdrawable(_grantee, testTokenAddr) + _newlyWithdrawable) {
            _reverted = true;
            vm.expectRevert();
        }
        metavestTest.withdraw(testTokenAddr, _amount);
        if (!_reverted && _amount != 0) {
            assertEq(
                _beforeGranteeBalance + _amount,
                testToken.balanceOf(_grantee),
                "grantee's balance should have increased by _amount"
            );
            assertGt(
                _beforeMetavestContractBalance,
                testToken.balanceOf(metavestTestAddr),
                "tokens not withdrawn from metavest"
            );
            assertGt(
                metavestTest.getMetavestDetails(_grantee).allocation.vestedTokensWithdrawn,
                _details.allocation.vestedTokensWithdrawn,
                "vested tokens withdrawn should have changed"
            );
            assertGt(
                metavestTest.getMetavestDetails(_grantee).allocation.unlockedTokensWithdrawn,
                _details.allocation.unlockedTokensWithdrawn,
                "unlocked tokens withdrawn should have changed"
            );
        }
        assertEq(
            _details.allocation.tokenStreamTotal,
            metavestTest.getMetavestDetails(_grantee).allocation.tokenStreamTotal,
            "tokenStreamTotal should not have changed"
        );
        assertEq(
            _details.allocation.tokensVested,
            metavestTest.getMetavestDetails(_grantee).allocation.tokensVested,
            "vested tracker should not have changed"
        );
        assertEq(
            _details.allocation.tokensUnlocked,
            metavestTest.getMetavestDetails(_grantee).allocation.tokensUnlocked,
            "unlocked tracker should not have changed"
        );
    }

    /// @dev mock a BaseCondition call
    function checkCondition() public view returns (bool) {
        return (baseCondition);
    }

    function _createBasicMilestoneMetavest(
        address _grantee,
        bool _transferable
    ) internal returns (MetaVesT.MetaVesTDetails memory) {
        MetaVesT.Milestone[] memory milestones = new MetaVesT.Milestone[](1);
        milestones[0].complete = false;
        milestones[0].milestoneAward = 100;
        address[] memory conditionContracts = new address[](1);
        conditionContracts[0] = address(this); // will call the mock checkCondition
        milestones[0].conditionContracts = conditionContracts;

        vm.assume(_grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: 1000,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: uint128(100),
                unlockingCliffCredit: uint128(1),
                vestingRate: uint160(10),
                vestingStartTime: uint48(2 ** 20),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(2 ** 20),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: testTokenAddr
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: false}),
            milestones: milestones,
            grantee: _grantee,
            transferable: _transferable
        });

        testToken.mintToken(AUTHORITY, 1100);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, 1100);

        vm.prank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, 1100);
        return _metavestDetails;
    }

    function _createBasicRTAMetavest(address _grantee) internal returns (MetaVesT.MetaVesTDetails memory) {
        vm.assume(_grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.RESTRICTED,
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: 1000,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: uint128(1),
                unlockingCliffCredit: uint128(1),
                vestingRate: uint160(10),
                vestingStartTime: uint48(2 ** 20),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(2 ** 20),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: testTokenAddr
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({
                repurchasePrice: 1,
                tokensRepurchasable: 1000,
                shortStopTime: uint48(2 ** 40)
            }),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: false}),
            milestones: emptyMilestones,
            grantee: _grantee,
            transferable: true
        });

        testToken.mintToken(AUTHORITY, 1001);
        testToken2.mintToken(AUTHORITY, 1000);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, 1001);
        vm.prank(AUTHORITY);
        testToken2.approve(metavestTestAddr, 1000);

        vm.prank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, 1001);
        return _metavestDetails;
    }

    function _createTokenOptionMetavest(address _grantee) internal returns (MetaVesT.MetaVesTDetails memory) {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.OPTION,
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: 1000,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: uint128(10),
                unlockingCliffCredit: uint128(1),
                vestingRate: uint160(10),
                vestingStartTime: uint48(block.timestamp),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(block.timestamp),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: testTokenAddr
            }),
            option: MetaVesT.TokenOption({
                exercisePrice: 1,
                tokensForfeited: uint208(0),
                shortStopTime: uint48(block.timestamp + 100000)
            }),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: false}),
            milestones: emptyMilestones,
            grantee: _grantee,
            transferable: true
        });

        testToken2.mintToken(_grantee, 10000);
        testToken.mintToken(AUTHORITY, 10000);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, 1100);
        vm.prank(_grantee);
        testToken2.approve(metavestTestAddr, 10000);

        vm.prank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, 1000);
        return _metavestDetails;
    }

    function _createWithdrawableMetavest(
        address _grantee,
        uint256 _unlocked,
        uint256 _vested
    ) internal returns (MetaVesT.MetaVesTDetails memory) {
        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _unlocked + _vested, // this variable has to be more than both, so just add them together for testing purposes since we're directly assigning
                tokenGoverningPower: 0,
                tokensVested: _vested,
                tokensUnlocked: _unlocked,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: 0,
                unlockingCliffCredit: 0,
                vestingRate: uint160(10),
                vestingStartTime: uint48(2 ** 20),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(2 ** 20),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: testTokenAddr
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: false}),
            milestones: emptyMilestones,
            grantee: _grantee,
            transferable: false
        });

        testToken.mintToken(AUTHORITY, _unlocked + _vested);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, _unlocked + _vested);

        vm.prank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, _unlocked + _vested);
        return _metavestDetails;
    }

    // same min function as MetaVesT.sol
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}
