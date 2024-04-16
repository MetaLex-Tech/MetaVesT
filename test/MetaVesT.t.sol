//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/MetaVesT.sol";
import "src/MetaVesTController.sol";

/// @dev foundry framework testing of MetaVesT.sol including mock tokens
/// NOTE: many MetaVesT functions are permissioned and conditions are house in MetaVesTController; see
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

    function testCreateMetavest(MetaVesT.MetaVesTDetails calldata _metavestDetails, uint256 _total) external {
        vm.assume(_metavestDetails.allocation.tokenContract == testTokenAddr);
        // milestones tested separately
        vm.assume(_metavestDetails.milestones.length == 0);

        vm.prank(controllerAddr);
        testToken.mintToken(controllerAddr, _total);

        metavestTest.createMetavest(_metavestDetails, _total);
        assertEq(_total, testToken.balanceOf(metavestTestAddr));
        assertEq(
            _metavestDetails.grantee,
            imetavest.metavestDetails(_metavestDetails.grantee).grantee,
            "metavestDetails not stored"
        );
        assertEq(metavestTest.amountLocked(_metavestDetails.grantee), _total, "amountLocked did not update");
    }

    function testUpdateTransferability(address _grantee, bool _isTransferable) external {
        vm.prank(controllerAddr);
        metavestTest.updateTransferability(_grantee, _isTransferable);

        assertTrue(
            imetavest.metavestDetails(_grantee).transferable == _isTransferable,
            "transferability did not update"
        );
    }

    function testUpdateUnlockRate(address _grantee, uint208 _unlockRate) external {
        vm.prank(controllerAddr);
        metavestTest.updateUnlockRate(_grantee, _unlockRate);

        assertEq(imetavest.metavestDetails(_grantee).allocation.unlockRate, _unlockRate, "unlockRate did not update");
    }

    function testUpdateStopTimes(address _grantee, uint48 _stopTime, uint48 _shortStopTime) external {
        vm.prank(controllerAddr);
        metavestTest.updateStopTimes(_grantee, _stopTime, _shortStopTime);
        MetaVesT.MetaVesTType _type = imetavest.metavestDetails(_grantee).metavestType;

        if (
            _type == MetaVesT.MetaVesTType.OPTION &&
            imetavest.metavestDetails(_grantee).option.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(
                imetavest.metavestDetails(_grantee).option.shortStopTime,
                _shortStopTime,
                "option shortStopTime did not update"
            );
        } else if (
            _type == MetaVesT.MetaVesTType.RESTRICTED &&
            imetavest.metavestDetails(_grantee).rta.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            assertEq(
                imetavest.metavestDetails(_grantee).rta.shortStopTime,
                _shortStopTime,
                "rta shortStopTime did not update"
            );
        }
        assertEq(imetavest.metavestDetails(_grantee).allocation.stopTime, _stopTime, "stopTime did not update");
    }

    function testUpdatePrice(address _grantee, uint256 _newPrice) external {
        vm.prank(controllerAddr);
        MetaVesT.MetaVesTType _type = imetavest.metavestDetails(_grantee).metavestType;
        if (_type == MetaVesT.MetaVesTType.ALLOCATION) vm.expectRevert();
        metavestTest.updatePrice(_grantee, _newPrice);

        if (_type == MetaVesT.MetaVesTType.OPTION) {
            assertEq(
                imetavest.metavestDetails(_grantee).option.exercisePrice,
                _newPrice,
                "option exercise price did not update"
            );
        } else if (_type == MetaVesT.MetaVesTType.RESTRICTED) {
            assertEq(
                imetavest.metavestDetails(_grantee).rta.repurchasePrice,
                _newPrice,
                "rta repurchase price did not update"
            );
        }
    }

    /// @dev mock a BaseCondition call
    function checkCondition() public view returns (bool) {
        return (baseCondition);
    }
}
