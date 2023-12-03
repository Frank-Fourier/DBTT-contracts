// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVault {
    function depositToVault(address depositor, uint256 amount) external;
}

struct Tranche {
    bytes32[] _merkleProof;
    uint256 _balance;
    bool _deposit;
}

contract MerkleDistributor is Ownable {
    using SafeERC20 for IERC20;

    event Claimed(address claimant, uint256 tranche, uint256 claimAmount);
    event TrancheAdded(
        uint256 tranche,
        bytes32 merkleRoot,
        uint256 totalAllocation
    );

    IERC20 public token;
    IVault public vault;

    // Mapping of week number to merkle roots
    mapping(uint256 => bytes32) public merkleRoots;

    // Mapping of the last claimed week for the user
    mapping(address => uint256) private lastUnclaimedTranche;

    uint256 public numTranches;

    constructor(IERC20 _token, IVault _vault) {
        token = _token;
        vault = _vault;
    }

    //get last unclaimed Tranche for a user
    function getLastUnclaimedTranche(address _claimant)
        public
        view
        returns (uint256)
    {
        return lastUnclaimedTranche[_claimant];
    }

    // Owner sets a new merkle root for a week's distribution
    function seedNewAllocations(
        bytes32 _merkleRoot,
        uint256 _totalAllocation
    ) public onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), _totalAllocation);

        uint256 trancheId = numTranches;
        merkleRoots[trancheId] = _merkleRoot;

        numTranches++;

        emit TrancheAdded(trancheId, _merkleRoot, _totalAllocation);
    }

    function claimWeek(
        uint256 _balance,
        bool _deposit,
        bytes32[] memory _merkleProof
    ) public {
        require(_balance > 0, "MerkleDistributor: No balance");
        require(_merkleProof.length > 0, "MerkleDistributor: No merkle proof");
        _claimWeek(msg.sender, _balance, _merkleProof);

        uint256 claimAmount = _deposit ? 0 : _balance;
        uint256 vaultAmount = _deposit ? _balance : 0;
        _disburse(msg.sender, claimAmount, vaultAmount);
    }

    function claimWeeks(Tranche[] memory tranches) public {
        uint256 weeksToClaim = numTranches -
                lastUnclaimedTranche[msg.sender];
        require(weeksToClaim > 0, "MerkleDistributor: No weeks to claim");
        require(tranches.length <= weeksToClaim, "MerkleDistributor: Too many tranches");
        uint256 totalClaimAmount;
        uint256 totalVaultAmount;
        // loop over each Tranche struct in Tranche[]
        for (uint256 i = 0; i < tranches.length; i++) {
            uint256 _balance = tranches[i]._balance;
            bool _deposit = tranches[i]._deposit;
            bytes32[] memory _merkleProof = tranches[i]._merkleProof;

            require(_balance > 0, "MerkleDistributor: No balance");
            require(
                _merkleProof.length > 0,
                "MerkleDistributor: No merkle proof"
            );

            _claimWeek(msg.sender, _balance, _merkleProof);

            uint256 claimAmount = _deposit ? 0 : _balance;
            uint256 vaultAmount = _deposit ? _balance : 0;

            totalClaimAmount += claimAmount;
            totalVaultAmount += vaultAmount;
        }

        _disburse(msg.sender, totalClaimAmount, totalVaultAmount);
    }

    function _claimWeek(
        address _claimant,
        uint256 _balance,
        bytes32[] memory _merkleProof
    ) private {
        require(
            lastUnclaimedTranche[_claimant] < numTranches,
            "Cannot claim for future week."
        );
        require(
            _verifyClaim(
                _claimant,
                lastUnclaimedTranche[_claimant],
                _balance,
                _merkleProof
            ),
            "Incorrect merkle proof."
        );

        lastUnclaimedTranche[_claimant]++;

        emit Claimed(_claimant, lastUnclaimedTranche[_claimant], _balance);
    }

    function _verifyClaim(
        address _claimant,
        uint256 _tranche,
        uint256 _balance,
        bytes32[] memory _merkleProof
    ) private view returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(_claimant, _balance));
        return MerkleProof.verify(_merkleProof, merkleRoots[_tranche], leaf);
    }

    // Sends the tokens to the claimant
    function _disburse(
        address _claimant,
        uint256 _claimAmount,
        uint256 _vaultAmount
    ) private {
        if (_claimAmount > 0) {
            token.safeTransfer(_claimant, _claimAmount);
        }

        if (_vaultAmount > 0) {
            token.safeApprove(address(vault), _vaultAmount);
            vault.depositToVault(_claimant, _vaultAmount);
        }
    }

    function checkUnclaimed(
        address _claimant
    ) public view returns (uint256 unclaimedTranches) {
        unclaimedTranches = numTranches - lastUnclaimedTranche[_claimant];
    }
}
