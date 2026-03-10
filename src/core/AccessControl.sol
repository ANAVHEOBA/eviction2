// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


abstract contract AccessControl {
    
    // Role identifiers
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // mapping: Role => Account => hasRole
    mapping(bytes32 => mapping(address => bool)) private _roles;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

  
    modifier hasRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    constructor() {
        // The deployer is the default admin
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    
    function _checkRole(bytes32 role, address account) internal view {
        if (!_roles[role][account]) {
            revert("AccessControl: account is missing required role");
        }
    }

    
    function hasRoleStatus(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    
    function grantRole(bytes32 role, address account) external hasRole(ADMIN_ROLE) {
        _grantRole(role, account);
    }

   
    function revokeRole(bytes32 role, address account) external hasRole(ADMIN_ROLE) {
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

   
    function _grantRole(bytes32 role, address account) internal {
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }
}
