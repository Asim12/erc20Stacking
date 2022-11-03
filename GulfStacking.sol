// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; //erc20 interface for rewards transfer
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
contract GulfStacking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    address public gulfTokenAddress;
    uint256 public stackingPrice; // Gulf Token
    uint256 public minimumStackAmount;
    uint constant SECONDS_PER_DAY = 24 * 60 * 60;
    int constant OFFSET19700101 = 2440588;
    uint256 public stackingChargesAmount;
    uint256 public panalityAmount;
    uint256 public totalRewardsDistributed;
    uint256 public totalstackedAmount;
    bool public stackingStatus;
    struct StackingUserDeatils {
        uint256 amountStaked;
        uint256 totalEarning;
        uint256 unclaimedRewards;
        uint256 timeOfLastUpdate;
        uint256 startTime;
        uint32 stackingPlan; //1 => 6 month,  2 => 1 year , 3 => 2 year 
        bool status;
    } 
    mapping(address => uint256) public claimedRewardsMonthCount;
    mapping(address => StackingUserDeatils) public stackingUserDeatil;
    mapping(address => bool) public unstackingRequests;
    mapping(uint256 => uint256) public rewardPercentage ;  
    address[] public requestWalletUnstack;
    address[] public stakerAddress;
    mapping(uint256 => uint256) public panelityPercentage;
    constructor() {
        gulfTokenAddress        =   0x6f9CbE318a6BD9a199BD947451F0F26609ccC4F6; // _gulfTokenAddress;
        minimumStackAmount      =   10000*10**18;  
        stackingPrice           =   188*10**18; 
        panelityPercentage[1]   =   2;
        panelityPercentage[2]   =   2;
        panelityPercentage[3]   =   3;
        rewardPercentage[1]     =   2;
        rewardPercentage[2]     =   2;
        rewardPercentage[3]     =   3;
        stackingStatus          =   true;
    }

    function updateRewardPercentage(uint256 pakage, uint256 newPercentage) public onlyOwner{
        require(newPercentage > 0, "you can not update zero percentage");
        require(pakage == 1 || pakage == 2 || pakage == 3, "Package not exists!");
        rewardPercentage[pakage] = newPercentage;
    }

    function updatePanalityPercentage(uint256 pakageNumber, uint256 newPercentage) public onlyOwner{
        require(newPercentage > 0, "you can not update zero percentage");
        require(pakageNumber == 1 || pakageNumber == 2 || pakageNumber == 3, "Package is not valid!");
        panelityPercentage[pakageNumber] = newPercentage;
    }

    function updateStackingPrice(uint256 newPrice) public onlyOwner {
        require(newPrice >= 0, "You can not set negetive Price!");
        stackingPrice = newPrice * 10**18;
    }

    function calculateRewards(address wallet, uint256 pendingMonth)internal view returns(uint256){
        uint256 amount = convertIntoOrignal(stackingUserDeatil[wallet].amountStaked);
        uint256 stackingPlan = stackingUserDeatil[wallet].stackingPlan;
        uint256 rewardPer = rewardPercentage[stackingPlan];
        uint256 percentage  = ((amount / 100)*  rewardPer); 
        uint256 totalRewards = uint256 (percentage * uint256(pendingMonth) ) ;
        return convertIntoGewi(totalRewards);
    }

    function calculatePercentageAmount(address wallet, uint256 _percentage) internal view returns(uint256){
        uint256 amount = convertIntoOrignal(stackingUserDeatil[wallet].amountStaked); 
        uint256 percentage  = (amount / 100) * _percentage ;
        uint256 totalPanality = convertIntoGewi(percentage);
        return convertIntoGewi(totalPanality);
    }

    function getBalance() internal view returns(uint256){
        return uint256(IERC20(gulfTokenAddress).balanceOf(msg.sender));
    }

    function renewPackage(uint32 newPackage) public {
        require(stackingStatus == true , "Staking is unavailable contact support!");
        require(stackingUserDeatil[msg.sender].status = true, "You can not renew your package because your current package is still in process");
        require(stackingUserDeatil[msg.sender].amountStaked >= (minimumStackAmount + stackingPrice), "Your staking amount is not valid please unstack and stack again");
        require(newPackage == 1 || newPackage == 2 || newPackage == 3, "Staking package is not valid!");
        require( (stackingUserDeatil[msg.sender].amountStaked - stackingPrice) >= minimumStackAmount, "You can not renew your package because your remaining amount is less than minimum amount of staking!");
        claimRewardNewStacking();
        uint256 remainingStackingAmount = (stackingUserDeatil[msg.sender].amountStaked - stackingPrice);
        stackingUserDeatil[msg.sender].amountStaked = remainingStackingAmount; // this is new amount previous one should be 0
        stackingUserDeatil[msg.sender].timeOfLastUpdate = block.timestamp;
        stackingUserDeatil[msg.sender].startTime = block.timestamp;
        stackingUserDeatil[msg.sender].stackingPlan = newPackage;
        stackingUserDeatil[msg.sender].totalEarning = 0;
        stackingChargesAmount += stackingPrice;
        totalstackedAmount -=  stackingPrice;
        stackingUserDeatil[msg.sender].status = false;
        claimedRewardsMonthCount[msg.sender] = 0;
    }

    function convertIntoGewi(uint256 _amount) internal pure returns(uint256){
        return (_amount > 0 ) ? _amount*10**18 : 0;
    }

    function convertIntoOrignal(uint256 _amount) internal pure returns(uint256){
        return (_amount > 0 ) ? _amount / (1*10**18)  : 0;
    }

    function stackingStatusUpdate(bool newStatus) public onlyOwner{
        stackingStatus  =   newStatus;
    }

    //send only amount fee will be added here
    function stackToken(uint256 _amount, uint32 _stackingPlan) external nonReentrant{
        require(stackingStatus == true , "Staking is off please contact support!");
        uint256 amount = convertIntoGewi(_amount);
        require(amount >= minimumStackAmount  , "You can not stake this amount because it is less than minimum amount needed");
        require(_stackingPlan == 1 || _stackingPlan == 2 || _stackingPlan == 3, "Your selected package is not valid!");
        require(stackingUserDeatil[msg.sender].stackingPlan == _stackingPlan || stackingUserDeatil[msg.sender].stackingPlan == 0, "Your staking package is mismatched please check and try again!");
        uint256 userBalance = getBalance();
        require(userBalance >= (_amount + stackingPrice), "You don't have sufficient balance for stacking!");
        if(stackingUserDeatil[msg.sender].amountStaked > 0){
            claimRewardNewStacking();
        }
        require(stackingUserDeatil[msg.sender].status == false, "Your package period is over please renew your package!");
        IERC20(gulfTokenAddress).approve(address(this), (amount + stackingPrice) );
        IERC20(gulfTokenAddress).transferFrom(msg.sender, address(this), (amount + stackingPrice) );
        stackingUserDeatil[msg.sender].amountStaked += amount ;
        stackingUserDeatil[msg.sender].timeOfLastUpdate = block.timestamp;
        if(stackingUserDeatil[msg.sender].stackingPlan == 0){
            stackingUserDeatil[msg.sender].startTime = block.timestamp;
            stackingUserDeatil[msg.sender].stackingPlan = _stackingPlan;
            stakerAddress.push(msg.sender);
        }
        stackingChargesAmount += stackingPrice;
        totalstackedAmount += amount;
    }

    function claimRewards() external nonReentrant{
        require(stackingUserDeatil[msg.sender].status == false, "You already claim your rewards you can not do twice");
        uint256 stackedTime = getMonth(block.timestamp , stackingUserDeatil[msg.sender].timeOfLastUpdate); // check stacked time
        require(stackedTime > 0, "Month is not completed you have to wait!");
        require(stackingUserDeatil[msg.sender].stackingPlan == 1 && claimedRewardsMonthCount[msg.sender] < 6 || stackingUserDeatil[msg.sender].stackingPlan == 2 && claimedRewardsMonthCount[msg.sender] < 12 || stackingUserDeatil[msg.sender].stackingPlan == 3 && claimedRewardsMonthCount[msg.sender] < 24, "Your rewards have been already claimed!");
        require(stackingUserDeatil[msg.sender].amountStaked > 0 , "Pending reward and staked amount both are zero");
        uint256 pendingMonths = getPendingMonths();
        require(pendingMonths > 0, "Your package is expired please renew");
        uint256 calculatedRewards = calculateRewards(msg.sender, pendingMonths);
        uint256 pendingRewards = (stackingUserDeatil[msg.sender].unclaimedRewards > 0) ? stackingUserDeatil[msg.sender].unclaimedRewards : 0 ;
        uint256 totalRewards = (calculatedRewards + pendingRewards) ;
        require(totalRewards > 0 , "You do not have any pending rewards");
        stackingUserDeatil[msg.sender].timeOfLastUpdate = block.timestamp; // Change logic
        stackingUserDeatil[msg.sender].unclaimedRewards = 0;
        IERC20(gulfTokenAddress).safeTransfer(msg.sender, totalRewards);
        stackingUserDeatil[msg.sender].totalEarning += totalRewards;
        if(stackingUserDeatil[msg.sender].stackingPlan == 1 && claimedRewardsMonthCount[msg.sender] >= 6 || stackingUserDeatil[msg.sender].stackingPlan == 2 && claimedRewardsMonthCount[msg.sender] >= 12 || stackingUserDeatil[msg.sender].stackingPlan == 3 && claimedRewardsMonthCount[msg.sender] >= 24 ){
            stackingUserDeatil[msg.sender].status = true;
        }
        totalRewardsDistributed += totalRewards;
        claimedRewardsMonthCount[msg.sender] += pendingMonths;
    }

    function claimRewardNewStacking() internal {
        uint256 pendingMonths = getPendingMonths();
        if(pendingMonths > 0 && stackingUserDeatil[msg.sender].stackingPlan == 1 && claimedRewardsMonthCount[msg.sender] < 6 || stackingUserDeatil[msg.sender].stackingPlan == 2 && claimedRewardsMonthCount[msg.sender] < 12 || stackingUserDeatil[msg.sender].stackingPlan == 3 && claimedRewardsMonthCount[msg.sender] < 24){ 
            uint256 totalRewards = calculateRewards(msg.sender, pendingMonths);
            stackingUserDeatil[msg.sender].unclaimedRewards += totalRewards;
            stackingUserDeatil[msg.sender].timeOfLastUpdate = block.timestamp; 
            claimedRewardsMonthCount[msg.sender] +=  pendingMonths;
        }
    }

    function submitRequestForUnstack() external nonReentrant {
        uint256 stackedTime = getMonth(block.timestamp , stackingUserDeatil[msg.sender].startTime); //check stacked time
        require(stackedTime >= 3, "You can not unstack you have to wait atleast 3 months");
        require(unstackingRequests[msg.sender] == false, "Your request is already summitted!");
        require(stackingUserDeatil[msg.sender].amountStaked > 0, "You do not have any Staked Tokens to unstake");
        require(getBalance() > 0, "You don't have suffient amount!"); 
        unstackingRequests[msg.sender] = true;
        requestWalletUnstack.push(msg.sender);
    }

    function approvedStackingRequest(address walletAddress) external onlyOwner{
        require(stackingUserDeatil[walletAddress].amountStaked > 0, "You do not have any Staked tokens to withdraw");
        require(unstackingRequests[walletAddress] == true, "We donot have any request against this address!");
        unStackToken(walletAddress); 
    }

    function unStackToken(address walletAddress) internal nonReentrant {
        require(stackingUserDeatil[walletAddress].amountStaked > 0, "You do not have any Staked tokens to withdraw!");
        uint256 pendingMonths = getPendingMonths();
        if(stackingUserDeatil[walletAddress].stackingPlan == 1 && claimedRewardsMonthCount[walletAddress] >= 6 || stackingUserDeatil[walletAddress].stackingPlan == 2 && claimedRewardsMonthCount[walletAddress] >= 12 || stackingUserDeatil[walletAddress].stackingPlan == 3 && claimedRewardsMonthCount[walletAddress] >= 24 ){
            stackingUserDeatil[walletAddress].unclaimedRewards += (pendingMonths > 0) ? calculateRewards(walletAddress, pendingMonths) : 0;
            IERC20(gulfTokenAddress).transferFrom(address(this), walletAddress, stackingUserDeatil[walletAddress].amountStaked);
        }else{
            uint256 totalPanalityAmount = stackingUserDeatil[walletAddress].totalEarning + calculatePercentageAmount(walletAddress, panelityPercentage[stackingUserDeatil[walletAddress].stackingPlan] );
            uint256 remainingAmount = stackingUserDeatil[walletAddress].amountStaked - totalPanalityAmount;
            panalityAmount += remainingAmount;
            IERC20(gulfTokenAddress).transferFrom(address(this), walletAddress, remainingAmount);
        }
        totalstackedAmount -= stackingUserDeatil[walletAddress].amountStaked;
        stackingUserDeatil[walletAddress].amountStaked = 0;
        stackingUserDeatil[walletAddress].startTime = block.timestamp;
        stackingUserDeatil[walletAddress].stackingPlan = 0;
        stackingUserDeatil[walletAddress].unclaimedRewards = 0;
        stackingUserDeatil[walletAddress].status = false;

        stackingUserDeatil[walletAddress].timeOfLastUpdate = block.timestamp;
        unstackingRequests[walletAddress] = false;
        claimedRewardsMonthCount[msg.sender] = 0;
    }

    function getMonth(uint fromTimestamp, uint toTimestamp) internal pure returns (uint month) {
        (uint fromYear, uint fromMonth,) = _daysToDate(fromTimestamp / SECONDS_PER_DAY);
        (uint toYear, uint toMonth,) = _daysToDate(toTimestamp / SECONDS_PER_DAY);
        month = toYear * 12 + toMonth - fromYear * 12 - fromMonth;
    }

    function _daysToDate(uint _days) internal pure returns (uint year, uint month, uint day) {
        int __days = int(_days);
        int L = __days + 68569 + OFFSET19700101;
        int N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int _month = 80 * L / 2447;
        int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;
        year = uint(_year);
        month = uint(_month);
        day = uint(_day);
    }

    function myStackingAmount(address wallet) public view returns(uint256) {
        return (stackingUserDeatil[wallet].amountStaked > 0) ? stackingUserDeatil[wallet].amountStaked : 0 ;
    }

    function myPendingRewards()public view returns(uint256){
        require(stackingUserDeatil[msg.sender].unclaimedRewards > 0  || stackingUserDeatil[msg.sender].amountStaked > 0 , "Pending reward and stacked amount both are zero");
        uint256 pendingMonths = getPendingMonths();
        uint256 rewards = (pendingMonths > 0) ? calculateRewards(msg.sender, pendingMonths) : 0 ;
        return (rewards + stackingUserDeatil[msg.sender].unclaimedRewards);
    }

    function withdraw() public onlyOwner { 
        require(panalityAmount > 0 || stackingChargesAmount > 0, "Insufficient Balance");
        IERC20(gulfTokenAddress).transfer(msg.sender, (panalityAmount + stackingChargesAmount) ); 
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function getPendingMonths() internal view returns(uint256){
        uint256 stackedTime = getMonth(block.timestamp , stackingUserDeatil[msg.sender].timeOfLastUpdate); //check stacked time
        uint256 pendingMonths;
        if(stackingUserDeatil[msg.sender].stackingPlan == 1){
            pendingMonths = (claimedRewardsMonthCount[msg.sender] + stackedTime <= 6) ? stackedTime : (6 - stackedTime);
        }else if(stackingUserDeatil[msg.sender].stackingPlan == 2 && claimedRewardsMonthCount[msg.sender] < 12){
            pendingMonths = (claimedRewardsMonthCount[msg.sender] + stackedTime <= 12) ? stackedTime : (12 - stackedTime);
        }else {
            pendingMonths = (claimedRewardsMonthCount[msg.sender] + stackedTime <= 24) ? stackedTime : (24 - stackedTime);
        }
        return pendingMonths;
    }

    function updateStartTime(uint256 newTime) external onlyOwner {
        stackingUserDeatil[msg.sender].timeOfLastUpdate = newTime;
    }
}