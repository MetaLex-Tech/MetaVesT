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
 * @notice     Deploy a new instance of MetaVesTController, which in turn deploys a new MetaVesT it controls
 *
 **/
contract MetaVesTFactory {
    event MetaVesT_Deployment(
        address newMetaVesT,
        address authority,
        address controller,
        address dao,
        address vestingAllocationFactory,
        address tokenOptionFactory,
        address restrictedTokenFactory
    );

    error MetaVesTFactory_ZeroAddress();

    constructor() { }

    /// @notice constructs a MetaVesT framework specifying authority address, DAO staking/voting contract address
    /// each individual grantee's MetaVesT will be initiated in the newly deployed MetaVesT contract, and deployed MetaVesTs are amendable by 'authority' via the controller contract
    /// @dev conditionals are contained in the deployed MetaVesT, which is deployed in the MetaVesTController's constructor(); the MetaVesT within the MetaVesTController is immutable, but the 'authority' which has access control within the controller may replace itself
    /// @param _authority: address which initiates and may update each MetaVesT, such as a BORG or DAO
    /// @param _dao: contract address which token may be staked and used for voting, typically a DAO pool, governor, staking address. Submit address(0) for no such functionality.
    function deployMetavestAndController(address _authority, address _dao, address _vestingAllocationFactory, address _tokenOptionFactory, address _restrictedTokenFactory ) external returns(address) {
        if(_vestingAllocationFactory == address(0) || _tokenOptionFactory == address(0) || _restrictedTokenFactory == address(0))
           revert MetaVesTFactory_ZeroAddress();
        metavestController _controller = new metavestController(_authority, _dao, _vestingAllocationFactory, _tokenOptionFactory, _restrictedTokenFactory);
        emit MetaVesT_Deployment(address(0), _authority, address(_controller), _dao, _vestingAllocationFactory, _tokenOptionFactory, _restrictedTokenFactory);
        return address(_controller);
    }

}
