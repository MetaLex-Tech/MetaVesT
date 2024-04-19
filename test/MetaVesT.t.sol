//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/MetaVesT.sol";
import "src/MetaVesTController.sol";

/// @dev foundry framework testing of MetaVesT.sol including mock tokens
/// NOTE: many MetaVesT functions are permissioned and conditions are housed in MetaVesTController that are assumed in here; see
/// MetaVesTController.t.sol for such tests
/// forge t --via-ir

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

/// @notice Second ERC20 token contract with 6 decimals
/// @dev not burnable or mintable
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

/// @notice test contract for MetaVesT using Foundry
contract MetaVesTTest is Test {
    address internal constant AUTHORITY = address(333);
    address internal constant DAO = address(444);

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

        metavestTest = new MetaVesT(AUTHORITY, controllerAddr, DAO, testPaymentToken);
        metavestTestAddr = address(metavestTest);
        imetavest = IMetaVesT(metavestTestAddr);
    }

    function testConstructor() public {
        assertEq(metavestTest.controller(), controllerAddr, "controller did not initialize");
        assertEq(metavestTest.authority(), AUTHORITY, "authority did not initialize");
        assertEq(metavestTest.dao(), DAO, "dao did not initialize");
        assertEq(metavestTest.paymentToken(), testPaymentToken, "paymentToken did not initialize");
    }

    function testCreateMetavest(address _grantee, uint256 _total, bool _transferable) external {
        vm.assume(_total > 1000 && _grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _total,
                cliffCredit: 0,
                tokenGoverningPower: 0,
                tokensUnlocked: 0,
                unlockedTokensWithdrawn: 0,
                unlockRate: 10,
                tokenContract: testTokenAddr,
                startTime: uint48(2 ** 20),
                stopTime: uint48(2 ** 40)
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({locked: false, unlocked: true, withdrawable: true}),
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
        assertEq(metavestTest.amountLocked(_metavestDetails.grantee), _total, "amountLocked did not update");
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

    function testUpdateUnlockRate(address _grantee, uint208 _unlockRate) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateUnlockRate(_grantee, _unlockRate);
        MetaVesT.MetaVesTDetails memory _details = metavestTest.getMetavestDetails(_grantee);
        assertEq(_details.allocation.unlockRate, _unlockRate, "unlockRate did not update");
    }

    function testUpdateStopTimes(address _grantee, uint48 _stopTime, uint48 _shortStopTime) external {
        vm.assume(_grantee != address(0));
        vm.startPrank(controllerAddr);
        metavestTest.updateStopTimes(_grantee, _stopTime, _shortStopTime);
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
        assertEq(_details.allocation.stopTime, _stopTime, "stopTime did not update");
    }

    function testUpdatePrice(address _grantee, uint256 _newPrice) external {
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

    function testConfirmMilestone(address _grantee, uint8 _milestoneIndex) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee);
        uint256 _beforeUnlocked = _details.allocation.tokensUnlocked;
        uint256 _beforeAmountLocked = metavestTest.amountLocked(_grantee);
        block.number / 2 == 0 ? baseCondition = true : baseCondition = false;

        bool _result;
        if (_milestoneIndex < _details.milestones.length)
            _result = ICondition(_details.milestones[_milestoneIndex].conditionContracts[0]).checkCondition();

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
                metavestTest.getMetavestDetails(_grantee).allocation.tokensUnlocked,
                _beforeUnlocked,
                "unlocked amount did not increase"
            );
            assertGt(_beforeAmountLocked, metavestTest.amountLocked(_grantee), "amountLocked mapping did not update");
        }
    }

    function testRemoveMilestone(address _grantee, uint8 _milestoneIndex) external {
        vm.assume(_grantee != address(0));
        MetaVesT.MetaVesTDetails memory _details = _createBasicMilestoneMetavest(_grantee);
        uint256 _beforeAmountLocked = metavestTest.amountLocked(_grantee);
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
            assertGt(_beforeAmountLocked, metavestTest.amountLocked(_grantee), "amountLocked not reduced");
        }
    }

    /// @dev mock a BaseCondition call
    function checkCondition() public view returns (bool) {
        return (baseCondition);
    }

    function _createBasicMilestoneMetavest(address _grantee) internal returns (MetaVesT.MetaVesTDetails memory) {
        MetaVesT.Milestone[] memory milestones = new MetaVesT.Milestone[](1);
        milestones[0].complete = false;
        milestones[0].milestoneAward = 1;
        address[] memory conditionContracts = new address[](1);
        conditionContracts[0] = address(this); // will call the mock checkCondition
        milestones[0].conditionContracts = conditionContracts;

        vm.assume(_grantee != address(0));

        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: 1000,
                cliffCredit: 0,
                tokenGoverningPower: 0,
                tokensUnlocked: 0,
                unlockedTokensWithdrawn: 0,
                unlockRate: 10,
                tokenContract: testTokenAddr,
                startTime: uint48(2 ** 20),
                stopTime: uint48(2 ** 40)
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({locked: false, unlocked: true, withdrawable: true}),
            milestones: milestones,
            grantee: _grantee,
            transferable: false
        });

        testToken.mintToken(AUTHORITY, 1001);
        vm.prank(AUTHORITY);
        testToken.approve(metavestTestAddr, 1001);

        vm.prank(controllerAddr);
        metavestTest.createMetavest(_metavestDetails, 1001);
        return _metavestDetails;
    }
}
