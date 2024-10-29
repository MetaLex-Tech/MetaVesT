//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.20;

/*
************************************
                            MetaVesTFactory
                                    ************************************
                                                                      */

import "./MetaVesTController.sol";
interface IMetaVesTController {
    function metavest() external view returns (address);
}

/**
 * @title      MetaVesT Factory
 *
 * @author     MetaLeX Labs, Inc.
 *
 * @notice     Factory contract to deploy new instances of MetaVesTController, which may initiate and affect individual MetaVesTs
 *
 **/
contract MetaVesTFactory {
    event MetaVesT_Deployment(
        address authority,
        address controller,
        address dao,
        address vestingAllocationFactory,
        address tokenOptionFactory,
        address restrictedTokenFactory
    );

    error MetaVesTFactory_ZeroAddress();

    constructor() {}

    /// @notice constructs a MetaVesT Controller and overall framework specifying authority address, DAO contract address, and each MetaVesT type factory address
    /// @dev conditionals are contained in the deployed MetaVesT Controller; the `authority` which has access control within the `_controller` may replace itself
    /// @param _authority address which initiates and may update each MetaVesT
    /// @param _dao DAO governance contract address which exercises control over ability of 'authority' to call certain functions via imposing conditions in the controller. Submit address(0) for no such functionality.
    /// @param _vestingFactory vesting allocation factory (VestingAllocationFactory.sol) contract address
    /// @param _tokenOptionFactory token option factory (TokenOptionFactory.sol) contract address
    /// @param _restrictedTokenFactory restricted token award factory (RestrictedTokenFactory.sol) contract address
    function deployMetavestAndController(
        address _authority,
        address _dao,
        address _vestingAllocationFactory,
        address _tokenOptionFactory,
        address _restrictedTokenFactory
    ) external returns (address) {
        if (
            _vestingAllocationFactory == address(0) ||
            _tokenOptionFactory == address(0) ||
            _restrictedTokenFactory == address(0)
        ) revert MetaVesTFactory_ZeroAddress();
        metavestController _controller = new metavestController(
            _authority,
            _dao,
            _vestingAllocationFactory,
            _tokenOptionFactory,
            _restrictedTokenFactory
        );
        emit MetaVesT_Deployment(
            _authority,
            address(_controller),
            _dao,
            _vestingAllocationFactory,
            _tokenOptionFactory,
            _restrictedTokenFactory
        );
        return address(_controller);
    }
}
