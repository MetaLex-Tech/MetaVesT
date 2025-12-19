import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {YearnDirectorCompSepolia2025} from "./lib/YearnDirectorCompSepolia2025.sol";
import {YearnDirectorComp2025} from "./lib/YearnDirectorComp2025.sol";
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

contract DeployYearnDirectorCompScript is Script {
    function run() public {
        runWithArgs(
            "MetaLexMetaVest.yearn.2025",
            vm.envUint("DEPLOYER_PRIVATE_KEY"),
            YearnDirectorCompSepolia2025.getDefault()
        );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey,
        YearnDirectorComp2025.Config memory config
    ) public returns (
        metavestController controller,
        YearnDirectorComp2025.GrantInfo[] memory,
        GnosisTransaction[] memory
    ) {
        bytes32 salt = keccak256(bytes(saltStr));
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployYearnDirectorCompControllersScript ===");
        console2.log("saltStr: %s", saltStr);
        console2.log("deployer: %s", deployer);
        console2.log("");

        YearnDirectorComp2025.GrantInfo[] memory grants = YearnDirectorComp2025.loadGrants();

        vm.startBroadcast(deployerPrivateKey);

        // (1) Deploy factories and controllers

        VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();
        TokenOptionFactory tokenOptionFactory = new TokenOptionFactory{salt: salt}();
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory{salt: salt}();

        config.controller = new metavestController{salt: salt}(
            config.authority, // _authority
            config.dao, // _dao
            address(vestingAllocationFactory),
            address(tokenOptionFactory),
            address(restrictedTokenFactory)
        );

        console2.log("Deployed controller: %s", address(config.controller));
        console2.log("");

        vm.stopBroadcast();

        // (2a) Prepare Safe txs (vesting token approval & grants creation)

        // Calculate total vesting token needed for all grants
        uint256 totalVestingTokenAmount = 0;
        for (uint256 i = 0; i < grants.length; i++) {
            totalVestingTokenAmount += grants[i].amount;
        }

        console2.log("Preparing Safe tx for approving vesting tokens...");
        GnosisTransaction[] memory provisionSafeTxs = new GnosisTransaction[](1);
        provisionSafeTxs[0] = GnosisTransaction({
            to: config.vestingToken,
            value: 0,
            data: abi.encodeWithSelector(
                ERC20.approve.selector,
                address(config.controller),
                totalVestingTokenAmount
            )
        });

        console2.log("Preparing Safe txs for grants creation:");
        GnosisTransaction[] memory grantSafeTxs = _generateGrantSafeTxs(config, grants);

        GnosisTransaction[] memory allSafeTxs = new GnosisTransaction[](provisionSafeTxs.length + grantSafeTxs.length);

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
            config.controller,
            grants,
            allSafeTxs
        );
    }

    function _generateGrantSafeTxs(
        YearnDirectorComp2025.Config memory config,
        YearnDirectorComp2025.GrantInfo[] memory grants
    ) internal returns (GnosisTransaction[] memory safeTxs) {
        safeTxs = new GnosisTransaction[](grants.length);

        for (uint256 i = 0; i < grants.length; i++) {
            YearnDirectorComp2025.GrantInfo memory grant = grants[i];

            safeTxs[i] = GnosisTransaction({
                to: address(config.controller),
                value: 0,
                data: abi.encodeWithSelector(
                    metavestController.createMetavest.selector,
                    metavestController.metavestType.Vesting,
                    grant.grantee,
                    BaseAllocation.Allocation({
                        tokenContract: config.vestingToken,
                        tokenStreamTotal: grant.amount,
                        vestingCliffCredit: config.vestingAndUnlockCliff,
                        unlockingCliffCredit: config.vestingAndUnlockCliff,
                        vestingRate: config.vestingAndUnlockRate,
                        vestingStartTime: config.vestingAndUnlockStartTime,
                        unlockRate: config.vestingAndUnlockRate,
                        unlockStartTime: config.vestingAndUnlockStartTime
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
            console2.log("");
        }
    }
}