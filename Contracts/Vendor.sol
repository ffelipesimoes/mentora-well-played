// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./Price.sol";
import "./MentoraWellPlayedToken.sol";

contract Vendor is Ownable, PriceConsumerMaticDollar, ReentrancyGuard, AccessControl, Pausable {

    // address purchase order index
    mapping(address => uint[]) public accountOrders;
    // HashPix->true
    mapping(bytes32 => bool) public placedPixOrdersHashes;
    //address on wantingList
    mapping(address => bool) public waitingList;
    
    mapping(address => uint256) public totalClaimableTokens;

    mapping( uint => Order ) public Orders;

    address private walletMultSign;


    enum Batch {
        BATCH_WAITING_LIST,
        BATCH_1,
        BATCH_2,
        BATCH_PUBLIC_SALE
    }

    enum PurchaseMethod {
        MATIC,
        PIX
    }

    struct Order {
        address account;
        uint256 mwpWeiAmount;
        Batch batch;
        PurchaseMethod purchaseMethod;
    }

//MPW Token
    MentoraWellPlayedToken MWPToken;
    uint256 public minimumMwpAmountInDolar;
    uint256 public maximumMwpAmountInDolar;

    uint256 public ordersIndex;
    uint256 public totalTokensSold;


    uint256 constant public PRICE_WAITING_LIST = 80*10**15;
    uint256 constant public PRICE_BATCH_1 = 90*10**15;
    uint256 constant public PRICE_BATCH_2 = 95*10**15;
    uint256 constant public PRICE_PUBLIC_SALE = 100*10**15;
    
//TOTAL SOLD PER BACTH
    uint256 public totalSoldWL;
    uint256 public totalSoldBatch1;
    uint256 public totalSoldBatch2;
    uint256 public totalSoldPL;


    uint256 constant public MAX_SUPPLY_WAITING_LIST = 2090000*10**18;
    uint256 constant public MAX_SUPPLY_BATCH_1 = 4180000*10**18;
    uint256 constant public MAX_SUPPLY_BATCH_2 = 6270000*10**18;
    uint256 constant public MAX_SUPPLY_PUBLIC_SALE = 8360000*10**18;

    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant PLACE_PIX_ORDER_ROLE = keccak256("PLACE_PIX_ORDER_ROLE");
    bytes32 public constant WAITING_LIST_WRITER_ROLE = keccak256("WAITING_LIST_WRITER_ROLE");
    bytes32 public constant MIN_MWP_WRITER_ROLE = keccak256("MIN_MWP_WRITER_ROLE");
    bytes32 public constant BATCH_LOCKER_ROLE = keccak256("BATCH_LOCKER_ROLE");

    //Flags
    bool public isP1;
    bool public isP2;
    bool public isPL;
    bool public isPauseWithdraw;
    bool public isPauseClaim;
    bool public isPausePL;
    bool public isPauseBuyMwp;

    error MinimumMwpAmount(uint256 amountProvided, uint256 minimum);
    error MinimumPurchaseInDolar(uint256 amountProvided, uint256 minimum);
    error MaximumPurchaseInDolar(uint256 amountProvided, uint256 minimum);
    error PixOrderAlreadyPlaced(uint256 mwpWeiAmount, address receiver, uint256 nonce);
    error InsufficientVendorBalance(uint256 vendorBalance, uint256 withdrawAmount);
    error AddressNotInWaitingList(address _address);
    error PurchaseLimit(uint mwpAmountRemains, uint mwpTryPurchase);
    error InvalidBatch(Batch batch);
    error readWLFailed(); 
    error BatchFailWriteOrder();
    error FailSendEdgePL(uint maticReturns);
    error FailedTransferClaim(uint amountMwp);
    error FailedWithdraw(uint amountMatic);
    error MinMatic(uint amount);
    error LowMwpWriteOrder(uint amountmwp);
    event Pause();
    event unPause();
    event PauseClaim();
    event unPauseClaim();
    event unPauseBuyPL();
    event PauseBuyPL();
    event PauseWithdraw();
    event PauseBuyMwp();
    event unPauseBuyMwp();
    event unPauseWithdraw();
    event Claim(address account, uint claimableTokens);

    event WaitingList(address indexed _address, bool isIn);
    event WriteOrder(uint index, address account, uint mwp, Batch batch, PurchaseMethod method);
    event CapPLExecessPix(address indexed account, uint indexed purchase, uint indexed restMwp);
    event MaticReturnsPL(address indexed _account, uint indexed purchase, uint indexed maticReturns);
    event Withdraw(address acount, uint amountMatic);
    event PlacePixOrder(uint mwpAmount, address receiver, uint nonce, bytes32 hash);

    constructor(address aggregator) PriceConsumerMaticDollar(aggregator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSE_ROLE, msg.sender);
        _grantRole(WITHDRAW_ROLE, msg.sender);
        _grantRole(PLACE_PIX_ORDER_ROLE, msg.sender);
        _grantRole(WAITING_LIST_WRITER_ROLE, msg.sender);
        _grantRole(MIN_MWP_WRITER_ROLE, msg.sender);
        _grantRole(BATCH_LOCKER_ROLE, msg.sender);
        setMinimumMwpAmountInDolar(10*10**18);
        setMaximumMwpAmountInDolar(10000*10**18);
    }

    modifier forbidZeroAddress(address _address){
        require(_address != address(0), "Put some valid address");
        _;
    }

    modifier minMatic(uint amountInMatic){
        uint amountInDolar = getPriceUSD(amountInMatic);
        if(amountInDolar < minimumMwpAmountInDolar){
            revert MinimumPurchaseInDolar(amountInDolar,minimumMwpAmountInDolar);
        }
        else{
            _;
        }
    }

    modifier maxMatic(uint amountInMatic){
        uint amountInDolar = getPriceUSD(amountInMatic);
        if(amountInDolar > maximumMwpAmountInDolar){
            revert MaximumPurchaseInDolar(amountInDolar, maximumMwpAmountInDolar);
        }
        else{
            _;
        }
    }

    modifier pixAlreadyDone(uint mwpAmount, address receiver, uint nonce){
        if (pixOrderAlreadyPlaced(mwpAmount, receiver, nonce)){
            revert PixOrderAlreadyPlaced(mwpAmount, receiver, nonce);
        }
        else{
            _;
        }
    }

// ------------------------PAUSE FUNCTION----------------
    function pause() public onlyRole(PAUSE_ROLE) {
        _pause();
        emit Pause();
    }

    function unpause() public onlyRole(PAUSE_ROLE) {
        _unpause();
        emit unPause();
    }

    function pauseWithdraw() public onlyRole(PAUSE_ROLE){
        isPauseWithdraw = true;
        emit PauseWithdraw();
    }

    function pauseClaim() public onlyRole(PAUSE_ROLE){
        isPauseClaim = true;
        emit PauseClaim();
    }

    function unpauseClaim() public onlyRole(PAUSE_ROLE){
        isPauseClaim = false;
        emit unPauseClaim();
    }

    function unpauseWithdraw() public onlyRole(PAUSE_ROLE){
        isPauseWithdraw = false;
        emit unPauseWithdraw();
    }
    

    function pauseBuyMwpMatic() public onlyRole(PAUSE_ROLE){
        isPauseBuyMwp = true;
        emit PauseBuyMwp();
    }

    function unpauseBuyMwpMatic() public onlyRole(PAUSE_ROLE){
        isPauseBuyMwp = false;  
        emit unPauseBuyMwp();
    }
    
    function pauseBuyPL() public onlyRole(PAUSE_ROLE){
        isPausePL = true;
        emit PauseBuyPL();
    }
    function unpauseBuyPL() public onlyRole(PAUSE_ROLE){
        isPausePL = false;
        emit unPauseBuyPL();
    }
//--------------------------------------------------------------------------------

    function setMwpAddress(address mwpAddress) public onlyRole(MIN_MWP_WRITER_ROLE){
        MWPToken = MentoraWellPlayedToken(mwpAddress);
    }

    function setMinimumMwpAmountInDolar(uint256 amountInDolar) public onlyRole(MIN_MWP_WRITER_ROLE) {
        if (amountInDolar < 10**18) {
            revert MinimumMwpAmount(amountInDolar, 10**18);
        }
        minimumMwpAmountInDolar = amountInDolar;
    }

    function setMaximumMwpAmountInDolar(uint amountInDolar) public onlyRole(MIN_MWP_WRITER_ROLE){
        if (amountInDolar < 10**18) {
            revert MinimumMwpAmount(amountInDolar, 10**18);
        }
        maximumMwpAmountInDolar = amountInDolar;
    }

    function setwalletMultSign(address _walletMultSign) public forbidZeroAddress(_walletMultSign) onlyRole(WITHDRAW_ROLE){
        walletMultSign = _walletMultSign;  
    }
//----------------------------------------------------------------------

    function placePixOrderHash(uint256 mwpWeiAmount, address receiver, uint256 nonce) internal {
        placedPixOrdersHashes[getOrderHash(mwpWeiAmount, receiver, nonce)] = true;
        bytes32 hash = getOrderHash(mwpWeiAmount, receiver, nonce);
        emit PlacePixOrder(mwpWeiAmount, receiver, nonce, hash);
    }

    function getOrderHash(uint256 mwpWeiAmount, address receiver, uint256 nonce) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(mwpWeiAmount, receiver, nonce));
    }

    function pixOrderAlreadyPlaced(uint256 mwpWeiAmount, address receiver, uint256 nonce) internal view returns(bool) {
        return placedPixOrdersHashes[getOrderHash(mwpWeiAmount, receiver, nonce)];
    }

//----------------------------Handle With WhiteList------------------------------
    function putAddressInWaitingList(address _address) external forbidZeroAddress(_address) onlyRole(WAITING_LIST_WRITER_ROLE) {
        waitingList[_address] = true;
        emit WaitingList(_address, true);
    }

    function removeAddressFromWaitingList(address _address) external forbidZeroAddress(_address) onlyRole(WAITING_LIST_WRITER_ROLE) {
        if (!waitingList[_address]) {
            revert AddressNotInWaitingList(_address);
        }
        waitingList[_address] = false;
        emit WaitingList(_address, false);
    }
//---------------------------------------------------------------------------------------
//Checks conform supply or Flag
    function whichBatchIs() public view returns(Batch batch){
        if(totalSoldBatch1 <= MAX_SUPPLY_BATCH_1){
            return Batch.BATCH_1;
        }
        else if(totalSoldBatch2 <= MAX_SUPPLY_BATCH_2){
            return Batch.BATCH_2;
        }
        else if(totalSoldPL <= MAX_SUPPLY_PUBLIC_SALE){
            return Batch.BATCH_PUBLIC_SALE;
        }
        else if(isPL){
            return Batch.BATCH_PUBLIC_SALE;
        }
        else if(isP2){
            return Batch.BATCH_2;
        }
        else{
            return Batch.BATCH_PUBLIC_SALE;
        }
    }
//-------------------------Handle With Prices------------------------------
    function mwpAmountperOneMatic(Batch batch) public view returns (uint){
        uint valueInDollarperOneMatic = getPriceDolarperMatic()*10**18;
        if(batch == Batch.BATCH_WAITING_LIST){
           return valueInDollarperOneMatic/(PRICE_WAITING_LIST);
        }
        else if(batch == Batch.BATCH_1){
        return valueInDollarperOneMatic/(PRICE_BATCH_1);
        }
        else if(batch == Batch.BATCH_2){
            return valueInDollarperOneMatic/(PRICE_BATCH_2);
        }
        else{
            return valueInDollarperOneMatic/(PRICE_PUBLIC_SALE);
        }
    }

    function maticAmountperOneMwp(Batch batch) public view returns (uint256){
        uint valueInDollarperOneMatic= getPriceDolarperMatic();
        if(batch == Batch.BATCH_WAITING_LIST){
            return PRICE_WAITING_LIST *10**18/valueInDollarperOneMatic;
        }
        else if(batch == Batch.BATCH_1){
        return  PRICE_BATCH_1 *10**18/valueInDollarperOneMatic;
        }
        else if(batch == Batch.BATCH_2){
            return  PRICE_BATCH_2 *10**18/valueInDollarperOneMatic;
        }
        else{
            return  PRICE_PUBLIC_SALE *10**18/valueInDollarperOneMatic;
        }
    }

    function mwpAmountGivenMatic(uint value, Batch batch) public view returns(uint){
        return (mwpAmountperOneMatic(batch)*value)/10**18;
    }

    function maticAmountGivenMwp(uint value, Batch batch) public view returns(uint){
        return (maticAmountperOneMwp(batch)*value)/10**18;
    }

    function remainsinMaticperBatch(Batch batch) public view returns(uint){
        if(batch == Batch.BATCH_WAITING_LIST){
            return (maticAmountGivenMwp( MAX_SUPPLY_WAITING_LIST, batch) - maticAmountGivenMwp(totalSoldWL,batch));
        }
        else if(batch == Batch.BATCH_1){
            return (maticAmountGivenMwp(MAX_SUPPLY_BATCH_1, batch) - maticAmountGivenMwp(totalSoldBatch1, batch));
        }
        else if(batch == Batch.BATCH_2){
            return (maticAmountGivenMwp(MAX_SUPPLY_BATCH_2, batch) - maticAmountGivenMwp(totalSoldBatch2, batch));
        }
        else if(batch == Batch.BATCH_PUBLIC_SALE){
            return (maticAmountGivenMwp(MAX_SUPPLY_PUBLIC_SALE,batch) - maticAmountGivenMwp(totalSoldPL, batch));
        }
        else{
            revert InvalidBatch(batch);
        }
    }

//-----------------------------------------------------------------------------
    function WLisOpen() public view returns(bool){
        if(totalSoldWL < MAX_SUPPLY_WAITING_LIST){
            return true;
        }
        else if(isP2){
            return false;
        }
        else{
            return false;
        }

    }
//---------------------------------------------------------
    function writeOrder(address _account, uint _tokens, Batch _batch, PurchaseMethod _method) private {

        Orders[ordersIndex].account = _account;
        Orders[ordersIndex].mwpWeiAmount = _tokens;
        Orders[ordersIndex].batch = _batch;
        Orders[ordersIndex].purchaseMethod = _method;
        totalClaimableTokens[_account] += _tokens;
        totalTokensSold += _tokens;
        accountOrders[_account].push(ordersIndex);
        ordersIndex++;
        if(_batch == Batch.BATCH_WAITING_LIST){
            totalSoldWL+= _tokens;
        }
        else if(_batch == Batch.BATCH_1){
            totalSoldBatch1 += _tokens;
        }
        else if(_batch == Batch.BATCH_2){
            totalSoldBatch2 += _tokens;
        }
        else if(_batch == Batch.BATCH_PUBLIC_SALE){
            totalSoldPL += _tokens;
        }
        else{
            revert BatchFailWriteOrder();
        }
        emit WriteOrder(ordersIndex -1, _account, _tokens, _batch, _method);
    }

//---------------------------------------------------- Buy With Matic -----------------------------------

    function BuyMwpWithMatic() public payable minMatic(msg.value) maxMatic(msg.value) {
        require(isPauseBuyMwp == false, "Buy mwp is pause");
        PurchaseMethod matic = PurchaseMethod.MATIC;
        if(WLisOpen() && waitingList[msg.sender] == true){
            buyMwpInWL(msg.sender, msg.value, matic);
        }
        else{
            Batch batch = whichBatchIs();
            if(batch == Batch.BATCH_1){
                buyMwpInBacth1(msg.sender,msg.value, matic);
            }
            else if(batch == Batch.BATCH_2){
                buyMwpInBacth2(msg.sender, msg.value, matic);
            }
            else if(batch == Batch.BATCH_PUBLIC_SALE){
                buyMwpInBacthPL(msg.sender, msg.value, matic);
            }
        }
    }

//--------------------------------------------------- Buy With Pix ----------------------------------------------
    function BuyMwpWithPix(address receiver, uint256 mwpAmount, uint nonce) public whenNotPaused forbidZeroAddress(receiver) onlyRole(PLACE_PIX_ORDER_ROLE) 
        pixAlreadyDone(mwpAmount, receiver, nonce) {
            
        PurchaseMethod pix = PurchaseMethod.PIX;
        placePixOrderHash(mwpAmount,receiver, nonce);
        if(WLisOpen() && waitingList[receiver] == true){
            buyMwpInWL(receiver, mwpAmount, pix);
        }
        else{
            Batch batch = whichBatchIs();
            if(batch == Batch.BATCH_1){
                buyMwpInBacth1(receiver, mwpAmount, pix);
            }
            else if(batch == Batch.BATCH_2){
                buyMwpInBacth2(receiver, mwpAmount, pix);
            }
            else if(batch == Batch.BATCH_PUBLIC_SALE){
                buyMwpInBacthPL(receiver, mwpAmount, pix);
            }
        }
    }

//------------------------------------------------------------------------------
    function buyMwpInWL(address _account, uint _value, PurchaseMethod _method) private forbidZeroAddress(_account) {
        Batch batchWL = Batch.BATCH_WAITING_LIST;
        PurchaseMethod matic = PurchaseMethod.MATIC;
        PurchaseMethod pix = PurchaseMethod.PIX;

        if(_method == matic){
            uint remainsInMatic = remainsinMaticperBatch(batchWL);
            if(remainsInMatic < _value){
                uint nextBatchinMatic = _value - remainsInMatic;
                uint mwpAmmountWL = mwpAmountGivenMatic(remainsInMatic, batchWL);
                writeOrder(_account, mwpAmmountWL, batchWL, matic);
                buyMwpInBacth1(_account, nextBatchinMatic, _method);
            }
            else{
                uint mwpAmount = mwpAmountGivenMatic(_value, batchWL);
                writeOrder(_account, mwpAmount, batchWL, matic);
            }
        }
        else if (_method == pix){
            uint mwpRemains = MAX_SUPPLY_WAITING_LIST - totalSoldWL;
            if(_value > mwpRemains){
                uint nextBatchinMwp = _value - mwpRemains;
                writeOrder(_account, mwpRemains, batchWL, pix);
                buyMwpInBacth1(_account, nextBatchinMwp, pix);
            }
            else{
                writeOrder(_account, _value, batchWL, pix);
            }
        }
    }

    function buyMwpInBacth1(address _account, uint _value, PurchaseMethod _method) private forbidZeroAddress(_account) {
        Batch batch1 = Batch.BATCH_1;
        PurchaseMethod matic = PurchaseMethod.MATIC;
        PurchaseMethod pix = PurchaseMethod.PIX;
        if(_method == matic){
            uint remainsInMatic = remainsinMaticperBatch(batch1);
            if(remainsInMatic < _value){
                uint nextBatchinMatic = _value - remainsInMatic;
                uint mwpAmmountWL = mwpAmountGivenMatic(remainsInMatic, batch1);
                writeOrder(_account, mwpAmmountWL, batch1, matic);
                buyMwpInBacth2(_account, nextBatchinMatic, _method);
            }
            else{
                uint mwpAmount = mwpAmountGivenMatic(_value, batch1);
                writeOrder(_account, mwpAmount, batch1, matic);
            }
        }
        else if (_method == pix){
            uint mwpRemains = MAX_SUPPLY_BATCH_1 - totalSoldBatch1;
            if(_value > mwpRemains){
                uint nextBatchinMwp = _value - mwpRemains;
                writeOrder(_account, mwpRemains, batch1, pix);
                buyMwpInBacth2(_account, nextBatchinMwp, pix);
            }
            else{
                writeOrder(_account, _value, batch1, pix);
            }
        }
    }

    function buyMwpInBacth2(address _account, uint _value, PurchaseMethod _method) private forbidZeroAddress(_account) {
        Batch batch2 = Batch.BATCH_2;
        PurchaseMethod matic = PurchaseMethod.MATIC;
        PurchaseMethod pix = PurchaseMethod.PIX;
        if(_method == matic){
            uint remainsInMatic = remainsinMaticperBatch(batch2);
            if(remainsInMatic < _value){
                uint nextBatchinMatic = _value - remainsInMatic;
                uint mwpAmmountWL = mwpAmountGivenMatic(remainsInMatic, batch2);
                writeOrder(_account, mwpAmmountWL, batch2, matic);
                buyMwpInBacthPL(_account, nextBatchinMatic, _method);
            }
            else{
                uint mwpAmount = mwpAmountGivenMatic(_value, batch2);
                writeOrder(_account, mwpAmount, batch2, matic);
            }
        }
        else if (_method == pix){
            uint mwpRemains = MAX_SUPPLY_BATCH_2 - totalSoldBatch2;
            if(_value > mwpRemains){
                uint nextBatchinMwp = _value - mwpRemains;
                writeOrder(_account, mwpRemains, batch2, pix);
                buyMwpInBacthPL(_account, nextBatchinMwp, pix);
            }
            else{
                writeOrder(_account, _value, batch2, pix);
            }
        }
    }

    function buyMwpInBacthPL(address _account, uint _value, PurchaseMethod _method) private forbidZeroAddress(_account) {
       require(!isPausePL, "PL is Pause");
        Batch PL = Batch.BATCH_PUBLIC_SALE;
        PurchaseMethod matic = PurchaseMethod.MATIC;
        PurchaseMethod pix = PurchaseMethod.PIX;
        if(_method == matic){
            uint remainsInMatic = remainsinMaticperBatch(PL);
            if(remainsInMatic < _value){
                uint mwpAmountRemains = mwpAmountGivenMatic(remainsInMatic, PL);
                uint mwpTryPurchase = mwpAmountGivenMatic(_value, PL);
                isPausePL = true;
                revert PurchaseLimit(mwpAmountRemains,mwpTryPurchase );
            }
            else{
                uint mwpAmount = mwpAmountGivenMatic(_value, PL);
                writeOrder(_account, mwpAmount, PL, matic);
            }
        }
        else if (_method == pix){
            uint mwpRemains = MAX_SUPPLY_BATCH_2 - totalSoldPL;
            if(_value > mwpRemains){
                uint nextBatchinMwp = _value - mwpRemains;
                writeOrder(_account, mwpRemains, PL, pix);
                emit CapPLExecessPix(_account, mwpRemains, nextBatchinMwp);
            }
            else{
                writeOrder(_account, _value, PL, pix);
            }
        }
    }
//-------------------------------------------------------------------------
    function getOrderPerAccount(address _account) public view returns ( uint[] memory){
        return accountOrders[_account];
    }
//------------------------------------------------------------------
    function claim() external nonReentrant  {
        require(!isPauseClaim, "Claim is Pause");
        uint256 vendorBalance = MWPToken.balanceOf(address(this));
        uint256 claimableTokens = totalClaimableTokens[msg.sender];
        if (vendorBalance < claimableTokens) {
            revert InsufficientVendorBalance(vendorBalance, claimableTokens);
        }
        totalClaimableTokens[msg.sender] = 0;
        (bool sent) = MWPToken.transfer(msg.sender, claimableTokens);
        if (!sent) {
            revert FailedTransferClaim(claimableTokens);
        }
        emit Claim(msg.sender, claimableTokens);
    }


    function withdraw() external  nonReentrant onlyRole(WITHDRAW_ROLE) {
        require(!isPauseWithdraw, "Withdraw is Pause");
        require (walletMultSign != address(0), "No valid wallet");
        uint256 amount = address(this).balance;
        if (amount == 0) {
            revert InsufficientVendorBalance(0, 0);
        }
        (bool sent,) = payable(walletMultSign).call{value: amount}("");
        if (!sent) {
            revert FailedWithdraw(amount);
        }
        emit Withdraw(msg.sender, amount);
    }


}