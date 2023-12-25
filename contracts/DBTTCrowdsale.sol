// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface Oracle {
    function latestAnswer() external view returns (uint256);
}

// Interface for ERC20 tokens, defining standard functions.
interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

// Interface for Wrapped Ether (WETH).
interface IWETH {
    function deposit() external payable;

    function withdraw(uint wad) external;
}

// Ownable contract providing basic authorization control.
contract Ownable {
    address public owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // set owner to deployer
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // modifier to check if caller is owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    // transfer ownership to new address
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

// ReentrancyGuard contract to prevent reentrant calls.
contract ReentrancyGuard {
    bool private _notEntered;

    constructor() {
        _notEntered = true;
    }

    modifier nonReentrant() {
        require(_notEntered, "ReentrancyGuard: reentrant call");
        _notEntered = false;
        _;
        _notEntered = true;
    }
}

// Crowdfunding contract with referral and airdrop features.
contract CrowdfundingWithReferral is Ownable, ReentrancyGuard {
    // Structure to store user information.
    struct User {
        address referrer;
        uint256 totalAirdrop;
        uint256 lastAirdropPhase;
        uint256 totalPurchasedTokens;
        uint256 totalContributionUSDT;
        uint256 totalContributionETH;
        uint256 totalCommissionUSDT;
        uint256 totalCommissionETH;
        uint256 totalCommissionDBTT;
    }

    struct Presale {
        uint256 _presaleStartTime;
        uint256 _presaleEndTime;
        uint256 _vestingInterval;
        uint256 _referralDepth;
        uint256[] _commissionRates;
        uint256 _priceUSDTRate;
        uint256 _minUSDTContribution;
        uint256 _minETHContribution;
        uint256 _maxDBTTAllocation;
        uint256 _saleCapDBTT;
        uint256 _nextPriceUSDTRate;
    }

    // Mapping from user address to User struct.
    mapping(address => User) public users;

    // Addresses for USDT, WETH, and DBTT tokens.
    address public constant USDT = 0x4d527d0b4E5Fc7cb057EbdE78f1c69FFC337125B;
    address public constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address public constant DBTT = 0xe1fFB714B7A3A6b2e823d036e75076887382d6bB;
    IWETH private constant weth = IWETH(WETH);
    Oracle public constant priceFeed = Oracle(
        0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
    );

    // Commission rates for the referral program.
    uint256[] public commissionRates;

    // Various configuration parameters.
    uint256 public referralDepth;
    uint256 public priceUSDTRate;
    uint256 public nextPriceUSDTRate;
    uint256 public minUSDTContribution;
    uint256 public minETHContribution;
    uint256 public maxDBTTAllocation;
    uint256 public saleCapDBTT;
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    uint256 public vestingInterval;

    // Presale status tracking variables.
    uint256 public successTimestamp;
    bool public isPresaleOpened;
    bool public isPresaleSuccess;
    bool public isPresaleCancelled;
    bool public isCommissionDBTT;

    // Counters
    uint256 public globalCommissionETH;
    uint256 public globalCommissionUSDT;
    uint256 public globalCommissionDBTT;
    uint256 public globalTotalAirdrop;
    uint256 public globalCommissionETHPaid;
    uint256 public globalCommissionUSDTPaid;
    uint256 public globalCommissionDBTTPaid;
    uint256 public globalTotalAirdropClaimed;
    uint256 public totalPurchasedDBTT;
    uint256 public totalPurchasedDBTTClaimed;


    // Event for new contribution
    event NewContribution(
        address indexed contributor,
        uint256 amount,
        address indexed referrer
    );

    /////////////////////////////// GETTERS ///////////////////////////////

    // Retrieves the current price of ETH in USD
    function getETHPrice() public view returns (uint256) {
        return priceFeed.latestAnswer();
    }

    // Calculates the total commission based on commission rates.
    function getTotalCommission() public view returns (uint256) {
        uint256 totalCommission = 0;
        for (uint256 i = 0; i < commissionRates.length; i++) {
            totalCommission += commissionRates[i];
        }
        return totalCommission;
    }

    // Retrieves user details for a given address.
    function getUserDetails(
        address userAddress
    ) public view returns (User memory) {
        return users[userAddress];
    }

    // Determines the current vesting phase based on the timestamp.
    function getVestingPhase() public view returns (uint256) {
        if (vestingInterval > 0 && successTimestamp > 0) {
            uint256 vestingPhase = 0;
            if (block.timestamp >= successTimestamp + 4 * vestingInterval) {
                vestingPhase = 4;
            } else if (
                block.timestamp >= successTimestamp + 3 * vestingInterval
            ) {
                vestingPhase = 3;
            } else if (
                block.timestamp >= successTimestamp + 2 * vestingInterval
            ) {
                vestingPhase = 2;
            } else if (
                block.timestamp >= successTimestamp + 1 * vestingInterval
            ) {
                vestingPhase = 1;
            }
            return vestingPhase;
        } else return 0;
    }

    /////////////////////////////// SETTERS ///////////////////////////////

    // Sets the referrer for a specific contributor.
    function setReferrer(address contributor, address referrer) internal {
        require(referrer != contributor, "Cannot refer self");
        users[contributor].referrer = referrer;
    }

    // Sets airdrop amounts for a list of addresses.
    function setAirdropList(
        address[] calldata airdropList,
        uint256 airdropAmount
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        require(
            airdropList.length < 251,
            "GAS Error: max airdrop limit is 251 addresses"
        );

        for (uint256 i = 0; i < airdropList.length; i++) {
            users[airdropList[i]].totalAirdrop += airdropAmount;
        }

        globalTotalAirdrop += airdropList.length * airdropAmount;
    }

    // Sets airdrop amount for an individual address.
    function setUserAirdrop(
        address userAddress,
        uint256 airdropAmount
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        globalTotalAirdrop -= users[userAddress].totalAirdrop;
        users[userAddress].totalAirdrop = airdropAmount;
        globalTotalAirdrop += airdropAmount;
    }

    // Sets the referral depth and corresponding commission rates.
    function setReferral(
        uint256 _referralDepth,
        uint256[] calldata _commissionRates
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        require(
            _commissionRates.length == _referralDepth,
            "Rates must have same depth"
        );
        referralDepth = _referralDepth;
        commissionRates = _commissionRates;
    }

    // Function to set presale start time
    function setPresaleStartTime(uint256 _presaleStartTime) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        presaleStartTime = _presaleStartTime;
    }

    // Function to set presale end time
    function setPresaleEndTime(uint256 _presaleEndTime) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        presaleEndTime = _presaleEndTime;
    }

    // Function to set vesting interval
    function setVestingInterval(uint256 _vestingInterval) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        vestingInterval = _vestingInterval;
    }

    // Function to set presale success
    function setPresaleSuccess(bool _isPresaleSuccess) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        if (_isPresaleSuccess) {
            isPresaleSuccess = true;
            successTimestamp = block.timestamp;
        } else {
            isPresaleCancelled = true;
        }
        isPresaleOpened = false;
    }

    // Function to set presale opened
    function setPresaleOpened(bool _isPresaleOpened) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        isPresaleOpened = _isPresaleOpened;
    }

    // Function to close presale
    function setPresaleClosed(
        bool _resetTime,
        bool _resetCap
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        isPresaleOpened = false;
        if (_resetTime) {
            presaleStartTime = 0;
            presaleEndTime = 0;
        }
        if (_resetCap) {
            maxDBTTAllocation = 0;
            saleCapDBTT = 0;
        }
    }

    // Function to set commission DBTT
    function setCommissionDBTT(bool _isCommissionDBTT) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        isCommissionDBTT = _isCommissionDBTT;
    }

    // Function to set price ETH rate
    function setPrice(
        uint256 _priceUSDTRate
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        priceUSDTRate = _priceUSDTRate;
    }

    // Function to set min USDT contribution
    function setMinUSDTContribution(
        uint256 _minUSDTContribution
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        minUSDTContribution = _minUSDTContribution;
    }

    // Function to set min ETH contribution
    function setMinETHContribution(
        uint256 _minETHContribution
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        minETHContribution = _minETHContribution;
    }

    // Function to set max DBTT allocation
    function setMaxAllocationDBTT(uint256 _maxAllocationDBTT) public onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        maxDBTTAllocation = _maxAllocationDBTT;
    }

    // Function to set sale cap DBTT
    function setSaleCapDBTT(uint256 _saleCapDBTT) public onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        saleCapDBTT = _saleCapDBTT;
    }

    // remove contribution limits
    function setRemoveContributionLimits() external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        minUSDTContribution = 0;
        minETHContribution = 0;
        maxDBTTAllocation = 0;
    }

    // set next price ETH and USDT rate
    function setNextPriceRates(
        uint256 _nextPriceUSDTRate
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        nextPriceUSDTRate = _nextPriceUSDTRate;
    }

    function setPresaleSettings(
        Presale calldata presaleConfig
    ) external onlyOwner {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        require(
            presaleConfig._commissionRates.length == presaleConfig._referralDepth,
            "Rates must have same depth"
        );
        if (
            presaleConfig._presaleStartTime > 0 &&
            presaleConfig._presaleEndTime > 0
        ) {
            require(
                presaleConfig._presaleStartTime < presaleConfig._presaleEndTime,
                "Start time must be before end time"
            );
        }
        if (presaleConfig._presaleStartTime > 0) {
            require(
                presaleConfig._presaleStartTime > block.timestamp,
                "Start time must be in the future"
            );
        }
        if (presaleConfig._presaleEndTime > 0) {
            require(
                presaleConfig._presaleEndTime > block.timestamp,
                "End time must be in the future"
            );
        }

        nextPriceUSDTRate = presaleConfig._nextPriceUSDTRate;

        // Set the referral program
        referralDepth = presaleConfig._referralDepth;
        commissionRates = presaleConfig._commissionRates;

        // Set the presale times
        presaleStartTime = presaleConfig._presaleStartTime;
        presaleEndTime = presaleConfig._presaleEndTime;

        // Set the vesting interval
        vestingInterval = presaleConfig._vestingInterval;

        // Set the token allocation and sale cap limits
        maxDBTTAllocation = presaleConfig._maxDBTTAllocation * 10 ** 18;
        saleCapDBTT = presaleConfig._saleCapDBTT * 10 ** 18;

        // Set the minimum contribution amounts
        minUSDTContribution = presaleConfig._minUSDTContribution;
        minETHContribution = presaleConfig._minETHContribution;

        priceUSDTRate = presaleConfig._priceUSDTRate;
    }

    /////////////////////////////// MAIN ///////////////////////////////

    function contributeWithETH(address referrer) external payable nonReentrant {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        if (presaleEndTime > 0 && block.timestamp >= presaleEndTime) {
            if (isPresaleOpened) isPresaleOpened = false;
            revert("Presale is closed");
        }
        require((isPresaleOpened || presaleStartTime > 0), "Presale is closed");
        if (presaleStartTime > 0) {
            require(
                block.timestamp >= presaleStartTime,
                "Presale has not started yet"
            );
            if (!isPresaleOpened) isPresaleOpened = true;
        }
        if (saleCapDBTT > 0) {
            require(totalPurchasedDBTT <= saleCapDBTT, "Sale cap reached");
        }
        if (minETHContribution > 0) {
            require(
                msg.value >= minETHContribution,
                "Amount must be greater than min contribution"
            );
        }

        require(msg.value > 0, "Amount must be greater than 0");
        weth.deposit{value: msg.value}();

        uint256 priceETHRate = getETHPrice() * priceUSDTRate / 10 ** 8;

        users[msg.sender].totalContributionETH += msg.value;
        uint256 allocation = msg.value * priceETHRate;

        if (maxDBTTAllocation > 0) {
            require(
                users[msg.sender].totalPurchasedTokens + allocation <=
                    maxDBTTAllocation,
                "Amount must be less than max allocation"
            );
        }
        if (saleCapDBTT > 0) {
            require(
                totalPurchasedDBTT + allocation <= saleCapDBTT,
                "Sale cap reached"
            );
        }
        users[msg.sender].totalPurchasedTokens += allocation;
        totalPurchasedDBTT += allocation;

        if (referrer != address(0)) {
            setReferrer(msg.sender, referrer);
        }

        // Distribute commissions (if applicable)
        distributeCommissions(msg.sender, WETH, msg.value); // Adjust this function as needed

        emit NewContribution(msg.sender, msg.value, referrer);
    }

    // Function to contribute with ERC20 tokens
    function contributeWithToken(
        address token,
        uint256 amount,
        address referrer
    ) external nonReentrant {
        require(!isPresaleSuccess && !isPresaleCancelled, "Presale is ended");
        if (presaleEndTime > 0 && block.timestamp >= presaleEndTime) {
            if (isPresaleOpened) isPresaleOpened = false;
            revert("Presale is closed");
        }
        require((isPresaleOpened || presaleStartTime > 0), "Presale is closed");
        if (presaleStartTime > 0) {
            require(
                block.timestamp >= presaleStartTime,
                "Presale has not started yet"
            );
            if (!isPresaleOpened) isPresaleOpened = true;
        }
        if (saleCapDBTT > 0) {
            require(totalPurchasedDBTT <= saleCapDBTT, "Sale cap reached");
        }
        if (minUSDTContribution > 0 && token == USDT) {
            require(
                amount >= minUSDTContribution,
                "Amount must be greater than min contribution"
            );
        }
        if (minETHContribution > 0 && token == WETH) {
            require(
                amount >= minETHContribution,
                "Amount must be greater than min contribution"
            );
        }
        require(amount > 0, "Amount must be greater than 0");
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Token allowance too low"
        );
        require(token == USDT || token == WETH, "ERC20 token not valid");

        // Transfer tokens to this contract
        bool sent = IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(sent, "Token transfer failed");

        uint256 allocation;
        if (token == USDT) {
            users[msg.sender].totalContributionUSDT += amount;
            allocation = (amount * priceUSDTRate) * 10 ** (12); // 18 - 6
        } else {
            users[msg.sender].totalContributionETH += amount;
            uint256 priceETHRate = getETHPrice() * priceUSDTRate / 10 ** 8;
            allocation = amount * priceETHRate;
        }

        if (maxDBTTAllocation > 0) {
            require(
                users[msg.sender].totalPurchasedTokens + amount <=
                    maxDBTTAllocation,
                "Amount must be less than max allocation"
            );
        }
        if (saleCapDBTT > 0) {
            require(
                totalPurchasedDBTT + allocation <= saleCapDBTT,
                "Sale cap reached"
            );
        }
        users[msg.sender].totalPurchasedTokens += allocation;
        totalPurchasedDBTT += allocation;

        if (referrer != address(0)) {
            setReferrer(msg.sender, referrer);
        }

        // Distribute commissions (if applicable)
        if (referralDepth > 0) {
            distributeCommissions(msg.sender, token, amount);
        }

        emit NewContribution(msg.sender, amount, referrer);
    }

    // Internal function to handle commission distribution
    function distributeCommissions(
        address contributor,
        address token,
        uint256 amount
    ) internal {
        address currentReferrer = users[contributor].referrer;

        for (uint256 i = 0; i < referralDepth; i++) {
            if (currentReferrer == address(0)) {
                break;
            }

            if (currentReferrer == contributor) {
                break;
            }

            uint256 commission = (amount * commissionRates[i]) / 100;

            if (isCommissionDBTT && token == USDT) {
                uint256 commissionDBTT = (commission * priceUSDTRate) / 10 ** 6;
                users[currentReferrer].totalCommissionDBTT += commissionDBTT;
                globalCommissionDBTT += commissionDBTT;
            } else if (isCommissionDBTT) {
                uint256 priceETHRate = getETHPrice() * priceUSDTRate / 10 ** 8;
                uint256 commissionDBTT = commission * priceETHRate;
                users[currentReferrer].totalCommissionDBTT += commissionDBTT;
                globalCommissionDBTT += commissionDBTT;
            } else if (token == USDT) {
                users[currentReferrer].totalCommissionUSDT += commission;
                globalCommissionUSDT += commission;
            } else {
                users[currentReferrer].totalCommissionETH += commission;
                globalCommissionETH += commission;
            }

            // Move to the next referrer
            currentReferrer = users[currentReferrer].referrer;
        }
    }

    // Function to withdraw commissions
    function withdrawCommissions() external nonReentrant {
        require(isPresaleSuccess, "Claim not active");
        require(
            users[msg.sender].totalCommissionUSDT > 0 ||
                users[msg.sender].totalCommissionETH > 0 ||
                users[msg.sender].totalCommissionDBTT > 0,
            "No commissions to claim"
        );

        _withdrawCommissions();
    }

    // Function to withdraw commissions
    function _withdrawCommissions() internal {
        uint256 amountUSDT = users[msg.sender].totalCommissionUSDT;
        if (amountUSDT > 0) {
            users[msg.sender].totalCommissionUSDT = 0;
            bool sent = IERC20(USDT).transfer(msg.sender, amountUSDT);
            require(sent, "Token transfer failed");
            globalCommissionUSDTPaid += amountUSDT;
        }
        uint256 amountETH = users[msg.sender].totalCommissionETH;
        if (amountETH > 0) {
            users[msg.sender].totalCommissionETH = 0;
            bool sent = IERC20(WETH).transfer(msg.sender, amountETH);
            require(sent, "Token transfer failed");
            globalCommissionETHPaid += amountETH;
        }
        uint256 amountDBTT = users[msg.sender].totalCommissionDBTT;
        if (amountDBTT > 0) {
            users[msg.sender].totalCommissionDBTT = 0;
            bool sent = IERC20(DBTT).transfer(msg.sender, amountDBTT);
            require(sent, "Token transfer failed");
            globalCommissionDBTTPaid += amountDBTT;
        }
    }

    // Function to withdraw purchased tokens
    function claimTokens() external nonReentrant {
        require(isPresaleSuccess, "Claim not active");
        require(users[msg.sender].totalPurchasedTokens > 0, "Nothing to claim");
        _claimTokens();
    }

    function _claimTokens() internal {
        uint256 amount = users[msg.sender].totalPurchasedTokens;
        users[msg.sender].totalPurchasedTokens = 0;

        bool sent = IERC20(DBTT).transfer(msg.sender, amount);
        require(sent, "Token transfer failed");
        totalPurchasedDBTTClaimed += amount;
    }

    // Function to withdraw ETH
    function withdrawETH() external onlyOwner nonReentrant {
        require(isPresaleSuccess, "Presale not yet completed");
        uint256 amount = IERC20(WETH).balanceOf(address(this));
        require(amount > globalCommissionETH - globalCommissionETHPaid, "Not enough ETH to withdraw");
        amount -= globalCommissionETH - globalCommissionETHPaid;
        bool sent = IERC20(WETH).transfer(msg.sender, amount);
        require(sent, "ETH Token transfer failed");
    }

    // Function to withdraw USDT
    function withdrawUSDT() external onlyOwner nonReentrant {
        require(isPresaleSuccess, "Presale not yet completed");
        uint256 amount = IERC20(USDT).balanceOf(address(this));
        require(amount > globalCommissionUSDT - globalCommissionUSDTPaid, "Not enough USDT to withdraw");
        amount -= globalCommissionUSDT - globalCommissionUSDTPaid;
        bool sent = IERC20(USDT).transfer(msg.sender, amount);
        require(sent, "USDT Token transfer failed");
    }

    // Function to withdraw DBTT
    function withdrawDBTT() external onlyOwner nonReentrant {
        uint256 amount = IERC20(DBTT).balanceOf(address(this));
        if (isPresaleSuccess) {
            require(
                amount > globalCommissionDBTT + totalPurchasedDBTT + globalTotalAirdrop - globalCommissionDBTTPaid - totalPurchasedDBTTClaimed - globalTotalAirdropClaimed,
                "Not enough DBTT to withdraw"
            );
            amount -= globalCommissionDBTT + totalPurchasedDBTT + globalTotalAirdrop - globalCommissionDBTTPaid - totalPurchasedDBTTClaimed - globalTotalAirdropClaimed;
            bool sent = IERC20(DBTT).transfer(msg.sender, amount);
            require(sent, "DBTT Token transfer failed");
        } else if (isPresaleCancelled && amount > 0) {
            bool sent = IERC20(DBTT).transfer(msg.sender, amount);
            require(sent, "DBTT Token transfer failed");
        } else revert("No DBTT to withdraw");
    }

    // refund USDT or WETH to user
    function refund() external nonReentrant {
        require(isPresaleCancelled, "Presale has not been cancelled");
        uint256 amountUSDT = users[msg.sender].totalContributionUSDT;
        uint256 amountETH = users[msg.sender].totalContributionETH;
        require(
            amountUSDT > 0 || amountETH > 0,
            "Amount must be greater than 0"
        );
        users[msg.sender].totalContributionUSDT = 0;
        users[msg.sender].totalContributionETH = 0;
        if (amountUSDT > 0) {
            bool sent = IERC20(USDT).transfer(msg.sender, amountUSDT);
            require(sent, "USDT Token transfer failed");
        }
        if (amountETH > 0) {
            bool sent = IERC20(WETH).transfer(msg.sender, amountETH);
            require(sent, "ETH Token transfer failed");
        }
    }

    // claim airdrop with vesting
    function claimAirdrop() external nonReentrant {
        require(isPresaleSuccess, "Claim not active");
        require(
            users[msg.sender].lastAirdropPhase <= 4,
            "Airdrop already claimed"
        );
        if (vestingInterval > 0) {
            require(
                getVestingPhase() > users[msg.sender].lastAirdropPhase,
                "Nothing to claim yet"
            );
            require(users[msg.sender].totalAirdrop > 0, "No airdrop for user");
        }

        _claimAirdrop();
    }

    function _claimAirdrop() internal {
        uint256 amount = users[msg.sender].totalAirdrop;
        if (vestingInterval > 0) {
            uint256 vestingPhase = getVestingPhase();
            uint256 vestingAmount = (amount *
                (vestingPhase - users[msg.sender].lastAirdropPhase)) / 4;
            users[msg.sender].lastAirdropPhase = vestingPhase;
            bool sent = IERC20(DBTT).transfer(msg.sender, vestingAmount);
            require(sent, "Token transfer failed");
            globalTotalAirdropClaimed += vestingAmount;
        } else {
            bool sent = IERC20(DBTT).transfer(msg.sender, amount);
            require(sent, "Token transfer failed");
            users[msg.sender].lastAirdropPhase = 4;
            globalTotalAirdropClaimed += amount;
        }
    }

    function claim() external nonReentrant {
        require(isPresaleSuccess, "Claim not active");
        require(
            users[msg.sender].totalCommissionUSDT > 0 ||
                users[msg.sender].totalCommissionETH > 0 ||
                users[msg.sender].totalCommissionDBTT > 0 ||
                users[msg.sender].totalPurchasedTokens > 0 ||
                (users[msg.sender].lastAirdropPhase <= 4 &&
                    getVestingPhase() > users[msg.sender].lastAirdropPhase &&
                    users[msg.sender].totalAirdrop > 0),
            "No commissions to claim"
        );
        if (
            users[msg.sender].totalCommissionUSDT > 0 ||
            users[msg.sender].totalCommissionETH > 0 ||
            users[msg.sender].totalCommissionDBTT > 0
        ) {
            _withdrawCommissions();
        }
        if (users[msg.sender].totalPurchasedTokens > 0) {
            _claimTokens();
        }
        if (
            users[msg.sender].lastAirdropPhase <= 4 &&
            getVestingPhase() > users[msg.sender].lastAirdropPhase &&
            users[msg.sender].totalAirdrop > 0
        ) {
            _claimAirdrop();
        }
    }
}
