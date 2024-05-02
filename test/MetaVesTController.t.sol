//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "src/MetaVesT.sol";
import "src/MetaVesTController.sol";

interface IWithdrawable {
    function getAmountWithdrawable(address _address, address _tokenContract) external view returns (uint256);
    function nonwithdrawableAmount(address _address) external view returns (uint256);
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

/// @notice test contract for MetaVesTController.sol using Foundry
/// @dev foundry framework testing of MetaVesTController.sol including mock tokens
contract MetaVesTControllerTest is Test {
    address internal constant AUTHORITY = address(3333);
    address internal constant DAO = address(4444);

    uint256 internal constant ARRAY_LENGTH_LIMIT = 20; // mirror internal variable in MetaVesTController
    uint256 internal constant AMENDMENT_TIME_LIMIT = 604800; // mirror internal variable in MetaVesTController

    uint48 internal _timestamp;

    TestToken internal testToken;
    TestToken2 internal testToken2;
    MetaVesTController internal controllerTest;
    IMetaVesT internal imetavest;

    MetaVesT.Milestone[] internal emptyMilestones;

    bool internal baseCondition;

    address metavestTestAddr;
    address controllerTestAddr;
    address testTokenAddr;
    address testToken2Addr; //paymentToken

    function setUp() public {
        testToken = new TestToken();
        testToken2 = new TestToken2();
        testTokenAddr = address(testToken);
        testToken2Addr = address(testToken2);
        controllerTest = new MetaVesTController(AUTHORITY, DAO, testToken2Addr);
        controllerTestAddr = address(controllerTest);

        metavestTestAddr = controllerTest.metavest();
        imetavest = IMetaVesT(metavestTestAddr);
    }

    function testConstructor() public {
        assertEq(controllerTest.authority(), AUTHORITY, "authority did not initialize");
        assertEq(controllerTest.paymentToken(), testToken2Addr, "paymentToken did not initialize");
        assertEq(controllerTest.dao(), DAO, "dao did not initialize");
    }

    function testCreateMetavestAndLockTokens(address _grantee, uint256 _streamTotal) external {
        vm.assume(_streamTotal < 1e50);
        bool _reverted;
        uint256 _total = _streamTotal + 100;
        MetaVesT.MetaVesTDetails memory _testDetails = _createBasicMilestoneMetavest(_grantee, _streamTotal); // foundry fails at calldata MetaVesTDetails and must use an ERC20
        MetaVesT.MetaVesTDetails memory _currentDetails = imetavest.getMetavestDetails(_testDetails.grantee);
        vm.startPrank(AUTHORITY);
        if (
            _currentDetails.grantee != address(0) ||
            _testDetails.grantee == address(0) ||
            _testDetails.allocation.tokenContract == address(0) ||
            _testDetails.allocation.tokenContract != testTokenAddr ||
            _testDetails.allocation.vestingCliffCredit > _testDetails.allocation.tokenStreamTotal ||
            _testDetails.allocation.unlockingCliffCredit > _testDetails.allocation.tokenStreamTotal ||
            _testDetails.allocation.vestingStopTime <= _testDetails.allocation.vestingStartTime ||
            _testDetails.allocation.unlockStopTime <= _testDetails.allocation.unlockStartTime ||
            (_testDetails.metavestType == MetaVesT.MetaVesTType.OPTION && _testDetails.option.exercisePrice == 0) ||
            (_testDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED && _testDetails.rta.repurchasePrice == 0) ||
            _testDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            _total > type(uint256).max ||
            testToken.allowance(controllerTest.authority(), metavestTestAddr) < _total ||
            testToken.balanceOf(controllerTest.authority()) < _total
        ) {
            _reverted = true;
            vm.expectRevert();
        }

        controllerTest.createMetavestAndLockTokens(_testDetails);
        if (!_reverted) {
            MetaVesT.MetaVesTDetails memory _newDetails = imetavest.getMetavestDetails(_testDetails.grantee);
            assertEq(_total, testToken.balanceOf(metavestTestAddr));
            assertEq(_testDetails.grantee, _newDetails.grantee, "metavestDetails grantee not stored");
            assertEq(
                _testDetails.allocation.tokenContract,
                _newDetails.allocation.tokenContract,
                "token Contract not stored"
            );
        }
    }

    function testProposeMetavestAmendment(address[] memory _affectedGrantees, bytes4 _msgSig) external {
        vm.assume(_affectedGrantees.length < ARRAY_LENGTH_LIMIT);
        for (uint256 i; i < _affectedGrantees.length; ++i) {
            vm.assume(_affectedGrantees[i] != address(0));
            MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_affectedGrantees[i]);
            if (_testDetails.grantee != _affectedGrantees[i]) {
                _testDetails = _createBasicMilestoneMetavest(_affectedGrantees[i], 1e20);
                vm.prank(AUTHORITY);
                controllerTest.createMetavestAndLockTokens(_testDetails);
            }
        }
        vm.startPrank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(_affectedGrantees, testTokenAddr, _msgSig);
        for (uint256 x; x < _affectedGrantees.length; ++x) {
            assertTrue(
                controllerTest.functionToGranteeToAmendmentPending(_msgSig, _affectedGrantees[x]),
                "amendment pending mapping did not update"
            );
        }
    }

    function testConsentToMetavestAmendment(address _caller, uint256 _elapsed, bytes4 _msgSig, bool _inFavor) external {
        vm.assume(_elapsed > 0 && _elapsed < AMENDMENT_TIME_LIMIT * 100000); // caller will not be able to consent the exact second an amendment is proposed
        vm.assume(_msgSig != bytes4(0));
        MetaVesT.MetaVesTDetails memory _testDetails = _createBasicMilestoneMetavest(_caller, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);

        address[] memory caller = new address[](1);
        caller[0] = _caller;
        bool _reverted;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(caller, testTokenAddr, _msgSig);

        vm.startPrank(_caller);
        controllerTest.consentToMetavestAmendment(_msgSig, _inFavor);

        uint256 _newTime = block.timestamp + _elapsed;
        vm.warp(_newTime);
        if (!controllerTest.functionToGranteeToAmendmentPending(_msgSig, _caller) || _elapsed >= AMENDMENT_TIME_LIMIT) {
            _reverted = true;
            vm.expectRevert();
        }
        controllerTest.consentToMetavestAmendment(_msgSig, _inFavor);

        if (!_reverted)
            assertTrue(
                controllerTest.functionToGranteeToMutualAgreement(_msgSig, _caller) == _inFavor,
                "grantee to mutual agreement mapping did not updated"
            );
    }

    function testUpdateTransferability(address _grantee, bool _isTransferable) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);

        // propose transferability amendment and consent to it
        bytes4 _sig = controllerTest.updateMetavestTransferability.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);

        vm.prank(AUTHORITY);
        controllerTest.updateMetavestTransferability(_grantee, _isTransferable);

        assertTrue(
            imetavest.getMetavestDetails(_grantee).transferable == _isTransferable,
            "transferability did not update"
        );
    }

    function testUpdateExerciseOrRepurchasePrice(address _grantee, uint128 _newPrice, bool _isRTA) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        //create metavest if it doesn't exist
        if (_testDetails.grantee != _grantee && _isRTA) _testDetails = _createBasicRTAMetavest(_grantee);
        else if (_testDetails.grantee != _grantee && !_isRTA) _testDetails = _createTokenOptionMetavest(_grantee);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);
        // propose transferability amendment and consent to it
        bytes4 _sig = controllerTest.updateExerciseOrRepurchasePrice.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);
        bool _reverted;

        vm.startPrank(AUTHORITY);
        if (_testDetails.metavestType == MetaVesT.MetaVesTType.ALLOCATION || _newPrice == uint128(0)) {
            _reverted = true;
            vm.expectRevert();
        }
        controllerTest.updateExerciseOrRepurchasePrice(_grantee, _newPrice);

        if (!_reverted && _testDetails.metavestType == MetaVesT.MetaVesTType.OPTION) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).option.exercisePrice,
                _newPrice,
                "option exercise price did not update"
            );
        } else if (!_reverted && _testDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).rta.repurchasePrice,
                _newPrice,
                "rta repurchase price did not update"
            );
        }
    }

    function testUpdateMetavestUnlockRate(address _grantee, uint160 _unlockRate) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);

        // propose transferability amendment and consent to it
        bytes4 _sig = controllerTest.updateMetavestUnlockRate.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);

        vm.prank(AUTHORITY);
        controllerTest.updateMetavestUnlockRate(_grantee, _unlockRate);
        MetaVesT.MetaVesTDetails memory _details = imetavest.getMetavestDetails(_grantee);
        assertEq(_details.allocation.unlockRate, _unlockRate, "unlockRate did not update");
    }

    function testUpdateMetavestVestingRate(address _grantee, uint160 _vestingRate) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);

        // propose amendment and consent to it
        bytes4 _sig = controllerTest.updateMetavestVestingRate.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);

        vm.prank(AUTHORITY);
        controllerTest.updateMetavestVestingRate(_grantee, _vestingRate);
        MetaVesT.MetaVesTDetails memory _details = imetavest.getMetavestDetails(_grantee);
        assertEq(_details.allocation.vestingRate, _vestingRate, "vestingRate did not update");
    }

    function testUpdateStopTimes(
        address _grantee,
        uint48 _unlockStopTime,
        uint48 _vestingStopTime,
        uint48 _shortStopTime,
        bool _isRTA
    ) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        //create metavest if it doesn't exist
        if (_testDetails.grantee != _grantee && _isRTA) _testDetails = _createBasicRTAMetavest(_grantee);
        else if (_testDetails.grantee != _grantee && !_isRTA) _testDetails = _createTokenOptionMetavest(_grantee);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);
        // propose amendment and consent to it
        bytes4 _sig = controllerTest.updateMetavestStopTimes.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);
        bool _reverted;

        if (_vestingStopTime < _shortStopTime) {
            _reverted = true;
            vm.expectRevert();
        }
        vm.prank(AUTHORITY);
        controllerTest.updateMetavestStopTimes(_grantee, _unlockStopTime, _vestingStopTime, _shortStopTime);

        // if short stop time already occurred it will not be updated
        if (
            !_reverted &&
            _testDetails.metavestType == MetaVesT.MetaVesTType.OPTION &&
            _testDetails.option.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).option.shortStopTime,
                _shortStopTime,
                "option shortStopTime did not update"
            );
        } else if (
            !_reverted &&
            _testDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED &&
            _testDetails.rta.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).rta.shortStopTime,
                _shortStopTime,
                "rta shortStopTime did not update"
            );
        }
        if (!_reverted) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).allocation.unlockStopTime,
                _unlockStopTime,
                "unlockStopTime did not update"
            );
            assertEq(
                imetavest.getMetavestDetails(_grantee).allocation.vestingStopTime,
                _vestingStopTime,
                "vestingStopTime did not update"
            );
        }
    }

    function testRemoveMilestone(address _grantee, uint8 _milestoneIndex) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);
        uint256 _beforeControllerWithdrawable = IWithdrawable(metavestTestAddr).getAmountWithdrawable(
            controllerTestAddr,
            testTokenAddr
        );
        uint256 _beforenonwithdrawableAmount = IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee);

        // propose transferability amendment and consent to it
        bytes4 _sig = controllerTest.removeMetavestMilestone.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);

        vm.prank(AUTHORITY);
        bool _reverted;
        if (_milestoneIndex >= _testDetails.milestones.length) {
            _reverted = true;
            vm.expectRevert();
        }
        controllerTest.removeMetavestMilestone(_grantee, _milestoneIndex);
        if (!_reverted) {
            assertEq(
                imetavest.getMetavestDetails(_grantee).milestones[_milestoneIndex].milestoneAward,
                0,
                "milestoneAward was not deleted"
            );
            assertGt(
                _beforenonwithdrawableAmount,
                IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee),
                "nonwithdrawableAmount not reduced"
            );
            assertGt(
                IWithdrawable(metavestTestAddr).getAmountWithdrawable(controllerTestAddr, testTokenAddr),
                _beforeControllerWithdrawable,
                "controller withdrawable amount not increased"
            );
        }
    }

    function testAddMilestone(address _grantee, uint48 _milestoneAward) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee, 10000);
        vm.prank(address(3));
        vm.expectRevert();
        imetavest.addMilestone(_grantee, _getMilestone(_milestoneAward));
        uint256 _beforeLocked = IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee);
        uint256 _beforeLength = _details.milestones.length;
        bool _reverted;
        testToken.mintToken(AUTHORITY, _milestoneAward);
        vm.startPrank(AUTHORITY);
        testToken.approve(metavestTestAddr, _milestoneAward);
        if (_milestoneAward == 0) {
            _reverted = true;
            vm.expectRevert();
        }
        imetavest.addMilestone(_grantee, _getMilestone(_milestoneAward));
        if (!_reverted) {
            assertGt(
                imetavest.getMetavestDetails(_grantee).milestones.length,
                _beforeLength,
                "milestones array did not increment length"
            );
            assertGt(
                IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee),
                _beforeLocked,
                "nonwithdrawableAmount did not increase"
            );
        }
    }

    function testTerminateMetavestVesting(address _grantee) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);
        uint256 _beforeBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _beforeAuthorityBalance = testToken.balanceOf(AUTHORITY);
        uint256 _beforeNonWithdrawable = IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee);

        vm.expectRevert();
        controllerTest.terminateMetavestVesting(_grantee);
        vm.prank(AUTHORITY);
        controllerTest.terminateMetavestVesting(_grantee);

        assertTrue(_beforeBalance >= testToken.balanceOf(metavestTestAddr), "metavest balance not properly changed");
        assertTrue(
            _beforeNonWithdrawable >= IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee),
            "grantee's balance not properly changed"
        );
        assertTrue(
            _beforeAuthorityBalance <= testToken.balanceOf(AUTHORITY),
            "authority's balance not properly changed"
        );
        assertEq(0, imetavest.getMetavestDetails(_grantee).allocation.vestingRate, "grantee's vestingRate not deleted");
        assertEq(
            0,
            imetavest.getMetavestDetails(_grantee).allocation.vestingCliffCredit,
            "grantee's vestingCliffCredit not deleted"
        );
    }

    function testTerminateMetavest(address _grantee) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        if (_testDetails.grantee != _grantee) _testDetails = _createBasicMilestoneMetavest(_grantee, 1e20);
        vm.prank(AUTHORITY);
        controllerTest.createMetavestAndLockTokens(_testDetails);

        // propose amendment and consent to it
        bytes4 _sig = controllerTest.terminateMetavest.selector;
        address[] memory grantee = new address[](1);
        grantee[0] = _grantee;
        vm.prank(AUTHORITY);
        controllerTest.proposeMetavestAmendment(grantee, testTokenAddr, _sig);
        vm.prank(_grantee);
        controllerTest.consentToMetavestAmendment(_sig, true);

        uint256 _beforeBalance = testToken.balanceOf(metavestTestAddr);
        uint256 _beforeGranteeBalance = testToken.balanceOf(_grantee);
        uint256 _beforeAuthorityBalance = testToken.balanceOf(AUTHORITY);
        uint256 _beforeLocked = IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee);
        uint256 _beforeWithdrawable = IWithdrawable(metavestTestAddr).getAmountWithdrawable(
            _grantee,
            _testDetails.allocation.tokenContract
        );
        uint256 _remainder = _beforeLocked -
            _testDetails.allocation.tokensVested -
            _testDetails.allocation.vestedTokensWithdrawn;
        if (_testDetails.metavestType != MetaVesT.MetaVesTType.OPTION)
            _beforeWithdrawable += _testDetails.allocation.tokensVested;
        else _remainder += _testDetails.allocation.tokensVested;

        vm.expectRevert();
        controllerTest.terminateMetavest(_grantee);
        vm.prank(AUTHORITY);
        controllerTest.terminateMetavest(_grantee);

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
            IWithdrawable(metavestTestAddr).getAmountWithdrawable(_grantee, testTokenAddr),
            "grantee still has withdrawable balance"
        );
        assertEq(
            0,
            IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee),
            "nonwithdrawableAmount not deleted"
        );
        assertEq(address(0), imetavest.getMetavestDetails(_grantee).grantee, "grantee's metavest not deleted");
    }

    function testRepurchaseMetavestTokens(address _grantee, uint256 _divisor) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _testDetails = imetavest.getMetavestDetails(_grantee);
        bool _preexisting = true;
        if (_testDetails.grantee != _grantee) {
            _preexisting = false;
            _testDetails = _createBasicRTAMetavest(_grantee);
        }
        // paymentToken mint and approve takes place in '_createBasicRTAMetavest'
        vm.startPrank(AUTHORITY);
        if (!_preexisting) controllerTest.createMetavestAndLockTokens(_testDetails);
        uint256 _beforeAuthorityBalance = testToken2.balanceOf(AUTHORITY);
        uint256 _amount;
        if (_divisor != 0) _amount = _testDetails.rta.tokensRepurchasable / _divisor;
        uint256 _beforeLocked = IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee);
        uint256 _beforePaymentTokenWithdrawable = IWithdrawable(metavestTestAddr).getAmountWithdrawable(
            _grantee,
            testToken2Addr
        );
        bool _reverted;
        if (
            _divisor == 0 ||
            _testDetails.rta.tokensRepurchasable == 0 ||
            block.timestamp >= _testDetails.rta.shortStopTime ||
            _testDetails.metavestType != MetaVesT.MetaVesTType.RESTRICTED
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        controllerTest.repurchaseMetavestTokens(_grantee, _divisor);

        if (!_reverted && _amount != 0) {
            assertGt(
                testToken2.balanceOf(AUTHORITY),
                _beforeAuthorityBalance,
                "authority's paymentToken balance not properly changed"
            );
            assertGt(
                _beforeLocked,
                IWithdrawable(metavestTestAddr).nonwithdrawableAmount(_grantee),
                "nonwithdrawableAmount not reduced by repurchased amount"
            );
            assertGt(
                _testDetails.allocation.tokenStreamTotal,
                imetavest.getMetavestDetails(_grantee).allocation.tokenStreamTotal,
                "tokenStreamTotal not reduced"
            );
            assertGt(
                _testDetails.rta.tokensRepurchasable,
                imetavest.getMetavestDetails(_grantee).rta.tokensRepurchasable,
                "tokensRepurchasable not reduced"
            );
            assertEq(
                _beforePaymentTokenWithdrawable + _amount,
                IWithdrawable(metavestTestAddr).getAmountWithdrawable(_grantee, testToken2Addr),
                "grantee's payment token withdrawable amount not increased by '_amount'"
            );
        }
    }
    /*

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
 */
    /// @dev mock a BaseCondition call
    function checkCondition() public view returns (bool) {
        return (baseCondition);
    }

    function _getMilestone(uint48 _milestoneAward) internal view returns (MetaVesT.Milestone memory) {
        MetaVesT.Milestone memory milestone;
        milestone.complete = false;
        milestone.milestoneAward = _milestoneAward;
        milestone.conditionContracts[0] = address(this); // will call the mock checkCondition
        return milestone;
    }

    function _createBasicMilestoneMetavest(
        address _grantee,
        uint256 _streamTotal
    ) internal returns (MetaVesT.MetaVesTDetails memory) {
        MetaVesT.Milestone[] memory milestones = new MetaVesT.Milestone[](2);
        milestones[0].complete = false;
        milestones[1].complete = false;
        milestones[0].milestoneAward = 50;
        milestones[1].milestoneAward = 50;
        address[] memory conditionContracts = new address[](2);
        conditionContracts[0] = address(this); // will call the mock checkCondition
        conditionContracts[1] = address(this);
        milestones[0].conditionContracts = conditionContracts;

        vm.assume(_grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _streamTotal,
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
            transferable: true
        });

        testToken.mintToken(AUTHORITY, _streamTotal + 100);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, _streamTotal + 100);
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
                tokensRepurchasable: 0,
                repurchasePrice: uint208(1),
                shortStopTime: uint48(2 ** 40)
            }),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: false}),
            milestones: emptyMilestones,
            grantee: _grantee,
            transferable: true
        });

        testToken.mintToken(AUTHORITY, 1001);
        testToken2.mintToken(AUTHORITY, 10000);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, 1001);
        vm.prank(AUTHORITY);
        testToken2.approve(metavestTestAddr, 10000);

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

        return _metavestDetails;
    }
    /*
    // same min function as MetaVesT.sol
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    } */
}
