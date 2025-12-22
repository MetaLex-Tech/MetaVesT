import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {AbstractBetaSepolia} from "./lib/AbstractBetaSepolia.sol";
import {AbstractBeta} from "./lib/AbstractBeta.sol";
import {SafeUtils} from "./lib/SafeUtils.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {GnosisTransaction} from "./lib/safe.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {RestrictedTokenAward} from "../src/RestrictedTokenAllocation.sol";
import {Script, console2} from "forge-std/Script.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";

contract DeployAbstractBetaScript is Script {
    function run() public {
        runWithArgs(
            // Ethereum mainnet
            "MetaLexMetaVest.Abstract.v1.0.0",
            vm.envUint("DEPLOYER_PRIVATE_KEY"),
            AbstractBetaSepolia.getDefault()

            // Sepolia
//            "MetaLexMetaVest.Abstract.v0.1.0",
//            vm.envUint("DEPLOYER_PRIVATE_KEY"),
//            AbstractBetaSepolia.getDefault()
        );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey,
        AbstractBeta.Config memory config
    ) public returns (
        metavestController controllerWithoutOverride,
        metavestController controllerWithOverride,
        AbstractBeta.GrantInfo[] memory,
        GnosisTransaction[] memory provisionSafeTxs,
        GnosisTransaction[] memory grantSafeTxs,
        GnosisTransaction[] memory allSafeTxs
    ) {
        bytes32 salt = keccak256(bytes(saltStr));
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployAbstractBetaControllersScript ===");
        console2.log("saltStr: %s", saltStr);
        console2.log("deployer: %s", deployer);
        console2.log("");

        AbstractBeta.GrantInfo[] memory grants = AbstractBeta.loadGrants();

        vm.startBroadcast(deployerPrivateKey);

        // (1) Deploy factories and controllers

        {
            VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();
            TokenOptionFactory tokenOptionFactory = new TokenOptionFactory{salt: salt}();
            RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory{salt: salt}();

            config.controllerWithoutOverride = new metavestController{salt: bytes32(uint256(salt) + 0)}(
                config.authority, // _authority
                config.dao, // _dao
                address(0), // _recipientOverride
                address(vestingAllocationFactory),
                address(tokenOptionFactory),
                address(restrictedTokenFactory)
            );

            config.controllerWithOverride = new metavestController{salt: bytes32(uint256(salt) + 1)}(
                config.authority, // _authority
                config.dao, // _dao
                config.escrowMultisig, // _recipientOverride
                address(vestingAllocationFactory),
                address(tokenOptionFactory),
                address(restrictedTokenFactory)
            );

            console2.log("Deployed controllers:");
            console2.log("  controllerWithoutOverride: ", address(config.controllerWithoutOverride));
            console2.log("  controllerWithOverride: ", address(config.controllerWithOverride));
            console2.log("");
        }

        vm.stopBroadcast();

        // (2a) Prepare Safe txs (vesting token approval & grants creation)

        // Calculate total vesting token needed for all grants
        uint256 totalVestingTokenAmountWithoutOverride = 0;
        uint256 totalVestingTokenAmountWithOverride = 0;
        for (uint256 i = 0; i < grants.length; i++) {
            if (grants[i].controllerType == AbstractBeta.ControllerType.WithoutOverride) {
                totalVestingTokenAmountWithoutOverride += grants[i].amount;
            } else {
                totalVestingTokenAmountWithOverride += grants[i].amount;
            }
        }

        console2.log("Preparing Safe tx for approving vesting tokens...");
        provisionSafeTxs = new GnosisTransaction[](2);
        provisionSafeTxs[0] = GnosisTransaction({
            to: config.vestingToken,
            value: 0,
            data: abi.encodeWithSelector(
                ERC20.approve.selector,
                address(config.controllerWithoutOverride),
                totalVestingTokenAmountWithoutOverride
            )
        });
        provisionSafeTxs[1] = GnosisTransaction({
            to: config.vestingToken,
            value: 0,
            data: abi.encodeWithSelector(
                ERC20.approve.selector,
                address(config.controllerWithOverride),
                totalVestingTokenAmountWithOverride
            )
        });

        console2.log("Preparing Safe txs for grants creation:");
        grantSafeTxs = _generateGrantSafeTxs(config, grants);

        allSafeTxs = new GnosisTransaction[](provisionSafeTxs.length + grantSafeTxs.length);

        // (2b) Create Safe txs JSON file

        {
            uint256 safeTxIdx = 0;
            for (uint256 i = 0; i < provisionSafeTxs.length; i++) {
                allSafeTxs[safeTxIdx++] = provisionSafeTxs[i];
            }
            for (uint256 i = 0; i < grantSafeTxs.length; i++) {
                allSafeTxs[safeTxIdx++] = grantSafeTxs[i];
            }

            string memory safeTxJson = SafeUtils.formatSafeTxJson(allSafeTxs);

            console2.log("Safe tx JSON (can be imported to Safe Transaction Builder):");
            console2.log("==== JSON data start ====");
            console2.log(safeTxJson);
            console2.log("==== JSON data end ====");

            string memory safeTxJsonPath = "./out/safeTxs.json";
            vm.writeJson(safeTxJson, safeTxJsonPath);
            console2.log("JSON file written to: %s", safeTxJsonPath);
        }

        return (
            config.controllerWithoutOverride,
            config.controllerWithOverride,
            grants,
            provisionSafeTxs,
            grantSafeTxs,
            allSafeTxs
        );
    }

    function _generateGrantSafeTxs(
        AbstractBeta.Config memory config,
        AbstractBeta.GrantInfo[] memory grants
    ) internal returns (GnosisTransaction[] memory safeTxs) {
        safeTxs = new GnosisTransaction[](grants.length);

        for (uint256 i = 0; i < grants.length; i++) {
            AbstractBeta.GrantInfo memory grant = grants[i];

            metavestController controller = _getController(grant, config);

            safeTxs[i] = GnosisTransaction({
                to: address(controller),
                value: 0,
                data: abi.encodeWithSignature(
                    "createMetavest(uint8,address,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)",
                    metavestController.metavestType.RestrictedTokenAward,
                    grant.grantee,
                    address(0), // no preference
                    BaseAllocation.Allocation({
                        tokenContract: config.vestingToken,
                        tokenStreamTotal: grant.amount,
                        vestingCliffCredit: grant.vestingCliffCredit,
                        unlockingCliffCredit: grant.unlockingCliffCredit,
                        vestingRate: grant.vestingRate,
                        vestingStartTime: grant.vestingStartTime,
                        unlockRate: grant.unlockRate,
                        unlockStartTime: config.unlockStartTime
                    }),
                    new BaseAllocation.Milestone[](0),
                    config.exercisePrice,
                    address(config.paymentToken),
                    config.shortStopDuration,
                    0 // no-op: _longStopDate
                )
            });

            console2.log("  #%d:", i + 1);
            console2.log("    grantee: %s", grant.grantee);
            console2.log("    amount: %d", grant.amount);
            console2.log("    vestingStartTime: %d", grant.vestingStartTime);
            console2.log("    vestingCliffCredit: %d", grant.vestingCliffCredit);
            console2.log("    vestingRate: %d", grant.vestingRate);
            console2.log("    unlockingCliffCredit: %d", grant.unlockingCliffCredit);
            console2.log("    unlockRate: %d", grant.unlockRate);
            console2.log("    controllerType: %d", uint8(grant.controllerType));
            console2.log("");
        }
    }

    function _getController(AbstractBeta.GrantInfo memory grant, AbstractBeta.Config memory config) internal returns (metavestController) {
        return (grant.controllerType == AbstractBeta.ControllerType.WithoutOverride)
            ? config.controllerWithoutOverride
            : config.controllerWithOverride;
    }
}
