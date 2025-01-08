// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract Governable {
    // keccak256("KING.governor");
    bytes32 private constant governorPosition =
        0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87;

    // keccak256("KING.pending.governor");
    bytes32 private constant pendingGovernorPosition =
        0x0fe544e960ecab9b6f1eee0df869972d09c3c135c0d116422cce176351b52237;

    event PendingGovernorshipTransfer(
        address indexed previousGovernor,
        address indexed newGovernor
    );

    event GovernorshipTransferred(
        address indexed previousGovernor,
        address indexed newGovernor
    );

    error OnlyGovernor();
    error OnlyPendingGovernor();
    error GovernorCannotBeAddressZero();

    /**
     * @notice Returns the address of the current Governor.
     */
    function governor() public view returns (address) {
        return _governor();
    }

    /**
     * @dev Returns the address of the current Governor.
     */
    function _governor() internal view returns (address governorOut) {
        bytes32 position = governorPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            governorOut := sload(position)
        }
    }

    /**
     * @dev Returns the address of the pending Governor.
     */
    function _pendingGovernor()
        internal
        view
        returns (address pendingGovernor)
    {
        bytes32 position = pendingGovernorPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            pendingGovernor := sload(position)
        }
    }

    /**
     * @dev Throws if called by any account other than the Governor.
     */
    modifier onlyGovernor() {
        if (!isGovernor()) revert OnlyGovernor();
        _;
    }

    /**
     * @notice Returns true if the caller is the current Governor.
     */
    function isGovernor() public view returns (bool) {
        return msg.sender == _governor();
    }

    function _setGovernor(address newGovernor) internal {
        bytes32 position = governorPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newGovernor)
        }
    }

    function _setPendingGovernor(address newGovernor) internal {
        bytes32 position = pendingGovernorPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newGovernor)
        }
    }

    /**
     * @notice Transfers Governance of the contract to a new account (`newGovernor`).
     * Can only be called by the current Governor. Must be claimed for this to complete
     * @param _newGovernor Address of the new Governor
     */
    function transferGovernance(address _newGovernor) external onlyGovernor {
        _setPendingGovernor(_newGovernor);
        emit PendingGovernorshipTransfer(_governor(), _newGovernor);
    }

    /**
     * @notice Claim Governance of the contract to a new account (`newGovernor`).
     * Can only be called by the new Governor.
     */
    function claimGovernance() external {
        if (msg.sender != _pendingGovernor()) revert OnlyPendingGovernor();
        _changeGovernor(msg.sender);
    }

    /**
     * @dev Change Governance of the contract to a new account (`newGovernor`).
     * @param _newGovernor Address of the new Governor
     */
    function _changeGovernor(address _newGovernor) internal {
        if (_newGovernor == address(0)) revert GovernorCannotBeAddressZero();
        emit GovernorshipTransferred(_governor(), _newGovernor);
        _setGovernor(_newGovernor);
    }
}
