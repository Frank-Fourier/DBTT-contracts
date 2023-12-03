// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MerkleDistributor.sol";

interface IDistributor {
    function seedNewAllocations(bytes32 _merkleRoot, uint256 _totalAllocation) external;
}

contract Vault is Ownable {
    using SafeERC20 for IERC20;

    struct Season {
        uint256 start;
        uint256 end;
        uint256 totalDeposits;
    }

    IERC20 public token;
    IDistributor public distributor;

    Season[] public seasons;
    mapping(address => mapping(uint256 => uint256)) public balances; // Mapping from depositor to season to balance
    mapping(uint256 => bool) public distributed;

    constructor(IERC20 _token) {
        token = _token;
        distributor = IDistributor(address(new MerkleDistributor(_token, IVault(address(this)))));
    }

    // number of seasons
    function numberOfSeasons() external view returns (uint256) {
        return seasons.length;
    }

    // for security we can define a fixed duration for each season
    function startNewSeason(uint256 _end) external onlyOwner {
        require(seasons.length == 0 || distributed[seasons.length - 1], "Distribute first!");
        require(_end > block.timestamp, "End must be in the future!");

        Season memory newSeason = Season({
            start: block.timestamp,
            end: _end,
            totalDeposits: 0
        });

        seasons.push(newSeason);
    }

    function depositToVault(address depositor, uint256 amount) external {
        require(amount > 0, "Deposit amount must be greater than zero.");
        require(seasons.length > 0, "Not yet available!");
        uint256 currentSeason = seasons.length - 1;
        require(block.timestamp >= seasons[currentSeason].start && block.timestamp <= seasons[currentSeason].end, "No active season.");

        balances[depositor][currentSeason] += amount;
        seasons[currentSeason].totalDeposits += amount;

        token.safeTransferFrom(depositor, address(this), amount);
    }

    function getCurrentBalance(address depositor) external view returns (uint256) {
        uint256 currentSeason = seasons.length - 1;
        return balances[depositor][currentSeason];
    }

    function getBalanceTranche(address depositor, uint256 trancheId) external view returns (uint256) {
        require(trancheId < seasons.length, "Invalid tranche Id.");
        return balances[depositor][trancheId];
    }

    function seedNewAllocations(bytes32 _merkleRoot, uint256 _totalAllocation) public onlyOwner {
        uint256 currentSeason = seasons.length - 1;
        require(block.timestamp >= seasons[currentSeason].end, "Current Season has not yet finished!");
        require(_totalAllocation <= token.balanceOf(address(this)), "Vault does not have enough tokens.");
        require(_totalAllocation > 0, "Can't allocate 0");
    
        // Approve the Distributor contract to spend the necessary amount of tokens
        token.approve(address(distributor), _totalAllocation);

        distributor.seedNewAllocations(_merkleRoot, _totalAllocation);
        distributed[seasons.length - 1] = true;
    }
}
