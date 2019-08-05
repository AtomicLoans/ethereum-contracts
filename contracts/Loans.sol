import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

import './Funds.sol';
import './Sales.sol';
import './DSMath.sol';
import './Medianizer.sol';

pragma solidity ^0.5.8;

contract Loans is DSMath {
    Funds funds;
    Medianizer med;
    Sales sales;

    uint256 public constant APEXT = 7200;         // approval expiration threshold
    uint256 public constant ACEXT = 172800;       // acceptance expiration threshold
    uint256 public constant BIEXT = 604800;       // bidding expirataion threshold

    mapping (bytes32 => Loan)         public loans;
    mapping (bytes32 => SecretHashes) public secretHashes; // Secret Hashes
    mapping (bytes32 => Bools)        public bools;        // Boolean state of Loan
    mapping (bytes32 => bytes32)      public fundIndex;    // Mapping of Loan Index to Fund Index
    mapping (bytes32 => ERC20)        public tokes;        // Mapping of Loan index to Token contract
    mapping (bytes32 => uint256)      public backs;        // Amount paid back in a Loan
    mapping (bytes32 => uint256)      public asaex;        // All Auction expiration
    uint256                           public loani;        // Current Loan Index

    ERC20 public token; // ERC20 Debt Stablecoin

    address deployer;

    struct Loan {
    	address bor;              // Address Borrower
        address lend;             // Address Lender
        address agent;            // Optional Address automated agent
        uint256 born;             // Created At
        uint256 loex;             // Loan Expiration
        uint256 prin;             // Principal
        uint256 interest;         // Interest
        uint256 penalty;          // Liquidation Penalty
        uint256 fee;              // Optional fee paid to auto if address not 0x0
        uint256 col;              // Collateral
        uint256 liquidationRatio; // Liquidation Ratio
        bytes   borrowerPubKey;   // Borrower PubKey
        bytes   lenderPubKey;     // Lender PubKey
    }

    struct SecretHashes {
    	bytes32    secretHashA1; // Secret Hash A1
    	bytes32[3] secretHashAs; // Secret Hashes A2, A3, A4 (for Sales)
    	bytes32    secretHashB1; // Secret Hash B1
    	bytes32[3] secretHashBs; // Secret Hashes B2, B3, B4 (for Sales)
    	bytes32    secretHashC1; // Secret Hash C1
    	bytes32[3] secretHashCs; // Secret Hashes C2, C3, C4 (for Sales)
    	bool       set;          // Secret Hashes set
    }

    struct Bools {
    	bool funded;        // Loan Funded
    	bool approved;      // Approve locking of collateral
    	bool taken;         // Loan Withdrawn
    	bool sale;          // Collateral Liquidation Started
    	bool paid;          // Loan Repaid
    	bool off;           // Loan Finished (Repayment accepted or cancelled)
    }

    function bor(bytes32 loan)    public view returns (address) {
        return loans[loan].bor;
    }

    function lend(bytes32 loan)   public view returns (address) {
        return loans[loan].lend;
    }

    function agent(bytes32 loan)  public view returns (address) {
        return loans[loan].agent;
    }

    function apex(bytes32 loan)   public returns (uint256) { // Approval Expiration
        return add(loans[loan].born, APEXT);
    }

    function acex(bytes32 loan)   public returns (uint256) { // Acceptance Expiration
        return add(loans[loan].loex, ACEXT);
    }

    function biex(bytes32 loan)   public returns (uint256) { // Bidding Expiration
        return add(loans[loan].loex, BIEXT);
    }

    function prin(bytes32 loan)   public view returns (uint256) {
        return loans[loan].prin;
    }

    function interest(bytes32 loan)   public view returns (uint256) {
        return loans[loan].interest;
    }

    function fee(bytes32 loan)   public view returns (uint256) {
        return loans[loan].fee;
    }

    function penalty(bytes32 loan)   public view returns (uint256) {
        return loans[loan].penalty;
    }

    function col(bytes32 loan)    public view returns (uint256) {
        return loans[loan].col;
    }

    function back(bytes32 loan)   public view returns (uint256) { // Amount paid back for loan
        return backs[loan];
    }

    function liquidationRatio(bytes32 loan)    public view returns (uint256) {
        return loans[loan].liquidationRatio;
    }

    function lent(bytes32 loan)   public view returns (uint256) { // Amount lent by Lender
        return add(prin(loan), interest(loan));
    }

    function lentb(bytes32 loan)  public view returns (uint256) { // Amount lent by lender minus amount paid back
        return sub(lent(loan), back(loan));
    }

    function owed(bytes32 loan)   public view returns (uint256) { // Amount owed
        return add(lent(loan), fee(loan));
    }

    function owedb(bytes32 loan)  public view returns (uint256) { // Amount owed minus amount paid back
        return sub(owed(loan), back(loan));
    }

    function dedu(bytes32 loan)   public view returns (uint256) { // Deductible amount from collateral
        return add(owed(loan), penalty(loan));
    }

    function dedub(bytes32 loan)  public view returns (uint256) { // Deductible amount from collateral minus amount paid back
        return sub(dedu(loan), back(loan));
    }

    function funded(bytes32 loan) public view returns (bool) {
        return bools[loan].funded;
    }

    function approved(bytes32 loan) public view returns (bool) {
        return bools[loan].approved;
    }

    function taken(bytes32 loan) public view returns (bool) {
        return bools[loan].taken;
    }

    function sale(bytes32 loan) public view returns (bool) {
        return bools[loan].sale;
    }

    function paid(bytes32 loan) public view returns (bool) {
        return bools[loan].paid;
    }

    function off(bytes32 loan)    public view returns (bool) {
        return bools[loan].off;
    }

    function colv(bytes32 loan) public returns (uint256) { // Current Collateral Value
        uint256 val = uint(med.read());
        return cmul(val, col(loan)); // Multiply value dependent on number of decimals with currency
    }

    function min(bytes32 loan) public view returns (uint256) {  // Minimum Collateral Value
        return rmul(sub(prin(loan), back(loan)), liquidationRatio(loan));
    }

    function safe(bytes32 loan) public returns (bool) { // Loan is safe from Liquidation
        return colv(loan) >= min(loan);
    }

    constructor (Funds funds_, Medianizer med_, ERC20 token_) public {
        deployer = msg.sender;
    	funds    = funds_;
    	med      = med_;
        token    = token_;
        require(token.approve(address(funds), 2**256-1));
    }

    function setSales(Sales sales_) external {
        require(msg.sender == deployer);
        require(address(sales) == address(0));
        sales = sales_;
    }
    
    function create(                   // Create new Loan
        uint256             loex_,     // Loan Expiration
        address[3] calldata usrs_,     // Borrower, Lender, Optional Automated Agent Addresses
        uint256[6] calldata vals_,     // Principal, Interest, Liquidation Penalty, Optional Automation Fee, Collaateral Amount, Liquidation Ratio
        bytes32             fundIndex_ // Optional Fund Index
    ) external returns (bytes32 loan) {
        loani = add(loani, 1);
        loan = bytes32(loani);
        loans[loan].born             = now;
        loans[loan].loex             = loex_;
        loans[loan].bor              = usrs_[0];
        loans[loan].lend             = usrs_[1];
        loans[loan].agent            = usrs_[2];
        loans[loan].prin             = vals_[0];
        loans[loan].interest         = vals_[1];
        loans[loan].penalty          = vals_[2];
        loans[loan].fee              = vals_[3];
        loans[loan].col              = vals_[4];
        loans[loan].liquidationRatio = vals_[5];
        fundIndex[loan]              = fundIndex_;
        secretHashes[loan].set       = false;
    }

    function setSecretHashes(                     // Set Secret Hashes for Loan
    	bytes32             loan,                 // Loan index
        bytes32[4] calldata borrowerSecretHashes, // Borrower Secret Hashes
        bytes32[4] calldata lenderSecretHashes,   // Lender Secret Hashes
        bytes32[4] calldata agentSecretHashes,    // Agent Secret Hashes
		bytes      calldata borrowerPubKey_,      // Borrower Pubkey
        bytes      calldata lenderPubKey_         // Lender Pubkey
	) external returns (bool) {
		require(!secretHashes[loan].set);
		require(msg.sender == loans[loan].bor || msg.sender == loans[loan].lend || msg.sender == address(funds));
		secretHashes[loan].secretHashA1 = borrowerSecretHashes[0];
		secretHashes[loan].secretHashAs = [ borrowerSecretHashes[1], borrowerSecretHashes[2], borrowerSecretHashes[3] ];
		secretHashes[loan].secretHashB1 = lenderSecretHashes[0];
		secretHashes[loan].secretHashBs = [ lenderSecretHashes[1], lenderSecretHashes[2], lenderSecretHashes[3] ];
		secretHashes[loan].secretHashC1 = agentSecretHashes[0];
		secretHashes[loan].secretHashCs = [ agentSecretHashes[1], agentSecretHashes[2], agentSecretHashes[3] ];
		loans[loan].borrowerPubKey      = borrowerPubKey_;
		loans[loan].lenderPubKey        = lenderPubKey_;
        secretHashes[loan].set          = true;
	}

	function fund(bytes32 loan) external { // Fund Loan
		require(secretHashes[loan].set);
    	require(bools[loan].funded == false);
    	require(token.transferFrom(msg.sender, address(this), prin(loan)));
    	bools[loan].funded = true;
    }

    function approve(bytes32 loan) external { // Approve locking of collateral
    	require(bools[loan].funded == true);
    	require(loans[loan].lend   == msg.sender);
    	require(now                <= apex(loan));
    	bools[loan].approved = true;
    }

    function take(bytes32 loan, bytes32 secretA1) external { // Withdraw
    	require(!off(loan));
    	require(bools[loan].funded == true);
    	require(bools[loan].approved == true);
    	require(sha256(abi.encodePacked(secretA1)) == secretHashes[loan].secretHashA1);
    	require(token.transfer(loans[loan].bor, prin(loan)));
    	bools[loan].taken = true;
    }

    function repay(bytes32 loan, uint256 amt) external { // Repay Loan
        // require(msg.sender                == loans[loan].bor); // NOTE: this is not necessary. Anyone can pay off the loan
    	require(!off(loan));
        require(!sale(loan));
    	require(bools[loan].taken         == true);
    	require(now                       <= loans[loan].loex);
    	require(add(amt, backs[loan])     <= owed(loan));

    	require(token.transferFrom(msg.sender, address(this), amt));
    	backs[loan] = add(amt, backs[loan]);
    	if (backs[loan] == owed(loan)) {
    		bools[loan].paid = true;
    	}
    }

    function refund(bytes32 loan) external { // Refund payback
    	require(!off(loan));
        require(!sale(loan));
    	require(now              >  acex(loan));
    	require(bools[loan].paid == true);
    	require(msg.sender       == loans[loan].bor);
        bools[loan].off = true;
    	require(token.transfer(loans[loan].bor, owed(loan)));
    }

    function cancel(bytes32 loan, bytes32 secret) external {
        accept(loan, secret, true); // Default to true for returning funds to Fund
    }

    function accept(bytes32 loan, bytes32 secret) external {
        accept(loan, secret, true); // Default to true for returning funds to Fund
    }

    function accept(bytes32 loan, bytes32 secret, bool fund) public { // Accept or Cancel // Bool fund set true if lender wants fund to return to fund
        require(!off(loan));
        require(bools[loan].taken == false || bools[loan].paid == true);
        require(msg.sender == loans[loan].lend || msg.sender == loans[loan].agent);
        require(sha256(abi.encodePacked(secret)) == secretHashes[loan].secretHashB1 || sha256(abi.encodePacked(secret)) == secretHashes[loan].secretHashC1);
        require(now                             <= acex(loan));
        require(bools[loan].sale                == false);
        bools[loan].off = true;
        if (bools[loan].taken == false) {
            require(token.transfer(loans[loan].lend, loans[loan].prin));
        } else if (bools[loan].taken == true) {
            if (fundIndex[loan] == bytes32(0) || !fund) {
                require(token.transfer(loans[loan].lend, lent(loan)));
            } else {
                funds.deposit(fundIndex[loan], lent(loan));
            }
            require(token.transfer(loans[loan].agent, fee(loan)));
        }
    }

    function sell(bytes32 loan) external returns (bytes32 sale) { // Start Auction
    	require(!off(loan));
        require(bools[loan].taken  == true);
    	if (sales.next(loan) == 0) {
    		if (now > loans[loan].loex) {
	    		require(bools[loan].paid == false);
			} else {
				require(!safe(loan));
			}
		} else {
			require(sales.next(loan) < 3);
			require(msg.sender == loans[loan].bor || msg.sender == loans[loan].lend);
            require(now > sales.setex(sales.salel(loan, sales.next(loan) - 1))); // Can only start auction after settlement expiration of pervious auction
            require(!sales.taken(sales.salel(loan, sales.next(loan) - 1))); // Can only start auction again if previous auction bid wasn't taken
		}
        SecretHashes storage h = secretHashes[loan];
        uint256 i = sales.next(loan);
		sale = sales.create(loan, loans[loan].bor, loans[loan].lend, loans[loan].agent, h.secretHashAs[i], h.secretHashBs[i], h.secretHashCs[i]);
        if (bools[loan].sale == false) { require(token.transfer(address(sales), back(loan))); }
		bools[loan].sale = true;
    }
}
