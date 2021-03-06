pragma solidity ^0.4.0;
contract POD_PhysicalItems{
    address public seller;
    address public buyer;
    address public transporter;
    address public arbitrator;//trusted incase of dispute
    address public attestaionAuthority; //party that attested the smart contract
    uint public itemPrice;
    bytes32 itemID;
    string public TermsIPFS_Hash;//Terms and conditions agreement IPFS Hash
    enum contractState {waitingForVerificationbySeller, waitingForVerificationbyTransporter, waitingForVerificationbyBuyer,
                        MoneyWithdrawn, PackageAndTransporterKeyCreated, ItemOnTheWay,PackageKeyGivenToBuyer, ArrivedToDestination, 
                        buyerKeysEntered, PaymentSettledSuccess, DisputeVerificationFailure, EtherWithArbitrator, 
                        CancellationRefund, Refund, Aborted}
    contractState public state;
    mapping(address=>bytes32) public verificationHash;
    mapping(address=>bool)cancellable;
    uint deliveryDuration;
    uint startEntryTransporterKeysBlocktime;
    uint buyerVerificationTimeWindow;
    uint startdeliveryBlocktime;
    //constructor
    function POD_PhysicalItems(){
        seller = 0xca35b7d915458ef540ade6068dfe2f44e8fa733c;
        buyer= 0x4b0897b0513fdc7c541b6d9d7e929c4e5364d2db;
        transporter = 0x14723a09acff6d2a60dcdf7aa4aff308fddc160c;
        arbitrator = 0x583031d1113ad414f02576bd6afabfb302140225;
        attestaionAuthority = 0xdd870fa1b7c4700f2bd7f44238821c26f7392148;
        itemPrice = 2 ether;
        itemID = 0x378032c1a780b9ab6b0e29afb705ee508a386ea90ef4969048ce0ae92fd0d6ad;
        deliveryDuration = 2 hours;//2 hours
        buyerVerificationTimeWindow = 15 minutes;//time for the buyer to verify keys after transporter entered the keys
        TermsIPFS_Hash = "QmWWQSuPMS6aXCbZKpEjPHPUZN2NjB3YrhJTHsV4X3vb2td";
        state = contractState.waitingForVerificationbySeller;
        cancellable[seller] = true;
        cancellable[buyer]=true;
        cancellable[transporter]=true;
    }
    
   modifier costs(){
       require(msg.value == 2*itemPrice);
       _;
   }
    modifier OnlySeller()
    {
        require(msg.sender == seller);
        _;
    }
    modifier OnlyBuyer(){
        require(msg.sender == buyer);
        _;
    }
    modifier OnlyTransporter(){
        require(msg.sender == transporter);
        _;
    }
    modifier OnlySeller_Buyer_Transporter(){
        require(msg.sender == seller || msg.sender == buyer || msg.sender == transporter);
        _;
    }
    event TermsAndConditionsSignedBy(string info, address entityAddress);
    event collateralWithdrawnSuccessfully(string info, address entityAddress);
    event PackageCreatedBySeller(string info, address entityAddress);
    event PackageIsOnTheWay(string info, address entityAddress);
    event PackageKeyGivenToBuyer(string info, address entityAddress);
    event ArrivedToDestination(string info, address entityAddress);
    event BuyerEnteredVerificationKeys(string info, address entityAddress);
    event SuccessfulVerification(string info);
    event VerificationFailure(string info);
    event CancellationReuest(address entityAddress, string info, string reason);
    event RefundDueToCancellation(string info);
    event DeliveryTimeExceeded(string info);
    event EtherTransferredToArbitrator(string info, address entityAddress);
    event BuyerExceededVerificationTime(string info, address entityAddress);
    
    function SignTermsAndConditions() payable costs OnlySeller_Buyer_Transporter{
        if(msg.sender == seller){
            require(state == contractState.waitingForVerificationbySeller);
            TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.waitingForVerificationbyTransporter;
        }else if(msg.sender == transporter)
        {
            require(state == contractState.waitingForVerificationbyTransporter);
            TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.waitingForVerificationbyBuyer;
        }
        else if(msg.sender == buyer){
            require(state == contractState.waitingForVerificationbyBuyer);
            TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.MoneyWithdrawn;

        }
    }
 
 function cancelTransaction(string reason)OnlySeller_Buyer_Transporter{
     require(cancellable[msg.sender] == true);
     state = contractState.CancellationRefund;
     //everyone gets a refund
     seller.transfer(2*itemPrice);
     buyer.transfer(2*itemPrice);
     transporter.transfer(2*itemPrice);
     CancellationReuest(msg.sender, " has requested a cancellation due to: ", reason );
     state = contractState.Aborted;
        selfdestruct(msg.sender);
 }
   
   //sender or transporter can cancel the transaction before the package is created with the key. 
    function createPackageAndKey() OnlySeller returns (string){
        require(state == contractState.MoneyWithdrawn);
        PackageCreatedBySeller("Package created and Key given to transporter by the sender ", msg.sender);
        state = contractState.PackageAndTransporterKeyCreated;
        cancellable[msg.sender] = false;
        cancellable[transporter]=false;
        return "0x378032c1a780b9ab6b0e29afb705ee";
    }
    //receiver can cancel as long as the package is not with the transporter
    function deliverPackage() OnlyTransporter{
        require(state == contractState.PackageAndTransporterKeyCreated);
        startdeliveryBlocktime = block.timestamp;//save the delivery time
        cancellable[buyer] = false;
        PackageIsOnTheWay("The package is being delivered and the key is received by the ", msg.sender);
        state = contractState.ItemOnTheWay;
    }
    
    function requestPackageKey() OnlyBuyer returns (string){
        require(state == contractState.ItemOnTheWay);
        PackageKeyGivenToBuyer("The package Key is given to the ", msg.sender);
        state = contractState.PackageKeyGivenToBuyer;
        return "0x508a386ea90ef4969048ce0ae92fd0d6ad"; 
    }
    
    function verifyTranspoter(string keyT, string keyR) OnlyTransporter{
        require(state == contractState.PackageKeyGivenToBuyer);
        ArrivedToDestination("Transporter Arrived To Destination and entered keys " , msg.sender);
        verificationHash[transporter] = keccak256(keyT, keyR);
        state = contractState.ArrivedToDestination;
        startEntryTransporterKeysBlocktime = block.timestamp;
    }
    function verifyKeyBuyer(string keyT, string keyR) OnlyBuyer{
        require(state == contractState.ArrivedToDestination);
        BuyerEnteredVerificationKeys("Reciever entered keys, waiting for payment settlement", msg.sender);
        verificationHash[buyer] = keccak256(keyT, keyR);
        state = contractState.buyerKeysEntered;
        verification();
    }
    function BuyerExceededTime() OnlyTransporter{
        require(block.timestamp > startEntryTransporterKeysBlocktime + buyerVerificationTimeWindow && 
        state == contractState.ArrivedToDestination);
        BuyerExceededVerificationTime("Dispute: Buyer Exceeded Verification Time", msg.sender);
        verification();
    }
    function refund()OnlyBuyer{//refund incase delivery took more than deadline
        require(block.timestamp > startdeliveryBlocktime+deliveryDuration &&
        (state == contractState.ItemOnTheWay || state == contractState.PackageKeyGivenToBuyer));
        DeliveryTimeExceeded("Item not delivered on time, Refund Request");
        state = contractState.Refund;
        buyer.transfer(2*itemPrice);
        seller.transfer(2*itemPrice);
         arbitrator.transfer(this.balance);//rest of ether with the arbitrator
         state = contractState.EtherWithArbitrator;
         EtherTransferredToArbitrator("Due to exceeding delivery time and refund request by receiver , all Ether deposits have been transferred to arbitrator ", arbitrator);
         state = contractState.Aborted;
         selfdestruct(msg.sender);
    }
    function verification() internal{
        require(state == contractState.buyerKeysEntered);
        if(verificationHash[transporter] == verificationHash[buyer]){
            SuccessfulVerification("Payment will shortly be settled , successful verification!");
            buyer.transfer(itemPrice);
            transporter.transfer((2*itemPrice) + ((10*itemPrice)/100));//receiver gets 10% of item price delivered
            seller.transfer((2*itemPrice)+((90*itemPrice)/100));
            state = contractState.PaymentSettledSuccess;
        }
        else {//trusted entity the Arbitrator resolves the issue
            VerificationFailure("Verification failed , keys do not match. Please solve the dispute off chain. No refunds.");
            state = contractState.DisputeVerificationFailure;
            arbitrator.transfer(this.balance);//all ether with the contract
            state = contractState.EtherWithArbitrator;
            EtherTransferredToArbitrator("Due to dispute all Ether deposits have been transferred to arbitrator ", arbitrator);
            state = contractState.Aborted;
            selfdestruct(msg.sender);
        }
    }
}