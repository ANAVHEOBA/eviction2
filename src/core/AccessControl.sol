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
    
    // Track admin count to prevent lockout
    uint256 private _adminCount;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
  
    modifier hasRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    constructor() {
        // The deployer is the default admin
        _adminCount = 0; // Initialize before granting
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
        require(account != address(0), "Cannot grant role to zero address");
        _grantRole(role, account);
    }

   
    function revokeRole(bytes32 role, address account) external hasRole(ADMIN_ROLE) {
        require(account != address(0), "Cannot revoke role from zero address");
        // SECURITY FIX: Prevent admin from revoking their own admin role
        if (role == ADMIN_ROLE) {
            if (msg.sender == account) {
                revert("Cannot revoke own admin role");
            }
            require(_hasOtherAdmin(account), "Cannot revoke last admin");
            if (_roles[role][account]) {
                _adminCount--;
            }
        }
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }
    
    function _hasOtherAdmin(address account) internal view returns (bool) {
        // CRITICAL FIX: Properly check if there are other admins
        // If revoking would leave 0 admins, prevent it
        if (_roles[ADMIN_ROLE][account]) {
            return _adminCount > 1;
        }
        return true; // Account doesn't have admin role, safe to proceed
    }

   
    function _grantRole(bytes32 role, address account) internal {
        if (role == ADMIN_ROLE && !_roles[role][account]) {
            _adminCount++;
        }
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }
}
