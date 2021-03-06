contract MasterChef is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeBEP20Upgradeable for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PLEARNs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPlearnPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPlearnPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. PLEARNs to distribute per block.
        uint256 lastRewardBlock; // Last block number that PLEARNs distribution occurs.
        uint256 accPlearnPerShare; // Accumulated PLEARNs per share, times 1e12. See below.
    }

    // The PLEARN TOKEN!
    PlearnToken public plearn;
    // The EARN TOKEN!
    PlearnEarn public earn;

    //Pools, Farms, Dev, Refs percent decimals
    uint256 public percentDec;
    //Pools and Farms percent from token per block
    uint256 public stakingPercent;
    //Developers percent from token per block
    uint256 public devPercent;
    //Referrals percent from token per block
    uint256 public refPercent;
    //Safu fund percent from token per block
    uint256 public safuPercent;

    // Dev address.
    address public devAddr;
    // Safu fund.
    address public safuAddr;
    // Refferals commision address.
    address public refAddr;

    // PLEARN tokens created per block.
    uint256 public plearnPerBlock;
    // Last block then develeper withdraw dev and ref fee
    uint256 public lastBlockDevWithdraw;
    // The block number when PLEARN mining starts.
    uint256 public startBlock;

    // Bonus muliplier for early plearn makers.
    uint256 public BONUS_MULTIPLIER;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    function initialize(
        PlearnToken _plearn,
        PlearnEarn _earn,
        address _devAddr,
        address _refAddr,
        address _safuAddr,
        uint256 _plearnPerBlock,
        uint256 _startBlock,
        uint256 _stakingPercent,
        uint256 _devPercent,
        uint256 _refPercent,
        uint256 _safuPercent
    ) public initializer {
        __Ownable_init();
        plearn = _plearn;
        earn = _earn;
        devAddr = _devAddr;
        refAddr = _refAddr;
        safuAddr = _safuAddr;
        plearnPerBlock = _plearnPerBlock;
        startBlock = _startBlock;
        stakingPercent = _stakingPercent;
        devPercent = _devPercent;
        refPercent = _refPercent;
        safuPercent = _safuPercent;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _plearn,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                accPlearnPerShare: 0
            })
        );

        percentDec = 1000000;
        BONUS_MULTIPLIER = 1;
        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function withdrawDevAndRefFee() public {
        require(lastBlockDevWithdraw < block.number, "wait for new block");
        uint256 multiplier = getMultiplier(lastBlockDevWithdraw, block.number);
        uint256 plearnReward = multiplier.mul(plearnPerBlock);
        plearn.mint(devAddr, plearnReward.mul(devPercent).div(percentDec));
        plearn.mint(safuAddr, plearnReward.mul(safuPercent).div(percentDec));
        plearn.mint(refAddr, plearnReward.mul(refPercent).div(percentDec));
        lastBlockDevWithdraw = block.number;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accPlearnPerShare: 0
            })
        );
    }

    // Update the given pool's PLEARN allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending PLEARNs on frontend.
    function pendingPlearn(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPlearnPerShare = pool.accPlearnPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 plearnReward = multiplier
                .mul(plearnPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint)
                .mul(stakingPercent)
                .div(percentDec);
            accPlearnPerShare = accPlearnPerShare.add(
                plearnReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accPlearnPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 plearnReward = multiplier
            .mul(plearnPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint)
            .mul(stakingPercent)
            .div(percentDec);

        plearn.mint(address(earn), plearnReward);
        pool.accPlearnPerShare = pool.accPlearnPerShare.add(
            plearnReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for PLEARN allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "deposit PLEARN by staking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accPlearnPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safePlearnTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPlearnPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "withdraw PLEARN by unstaking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPlearnPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safePlearnTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPlearnPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake PLEARN tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accPlearnPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safePlearnTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPlearnPerShare).div(1e12);

        earn.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw PLEARN tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accPlearnPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safePlearnTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPlearnPerShare).div(1e12);

        earn.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe plearn transfer function, just in case if rounding error causes pool to not have enough PLEARNs.
    function safePlearnTransfer(address _to, uint256 _amount) internal {
        earn.safePlearnTransfer(_to, _amount);
    }

    function setDevAddress(address _devaddr) public onlyOwner {
        devAddr = _devaddr;
    }

    function setRefAddress(address _refAddr) public onlyOwner {
        refAddr = _refAddr;
    }

    function setSafuAddress(address _safuAddr) public onlyOwner {
        safuAddr = _safuAddr;
    }

    function updatePlearnPerBlock(uint256 newAmount) public onlyOwner {
        plearnPerBlock = newAmount;
    }
}