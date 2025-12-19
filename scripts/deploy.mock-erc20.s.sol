import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract DeployMockErc20Script is Script {
    function run() public {

        string memory saltStr = "MetaLexMetaVest.Abstract.mockPaymentToken.dev.0";
        bytes32 salt = keccak256(bytes(saltStr));

        string memory tokenName = "Payment Token";
        string memory tokenSymbol = "PAY";
        uint8 tokenDecimals = 6;

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployMockErc20Script ===");
        console2.log("saltStr: %s", saltStr);
        console2.log("deployer: %s", deployer);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockToken = new MockERC20{salt: salt}(tokenName, tokenSymbol, tokenDecimals);
        console2.log("deployed mock token: %s", address(mockToken));

        vm.stopBroadcast();

        console2.log("Deployed addresses:");
        console2.log("  mock token: %s", address(mockToken));
        console2.log("  decimals: %d", mockToken.decimals());
        console2.log("");
    }
}