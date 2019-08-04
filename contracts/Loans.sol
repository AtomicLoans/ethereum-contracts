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

    mapping (bytes32 => Loan)      public loans;
    mapping (bytes32 => Sechs)     public sechs;  // Secret Hashes
    mapping (bytes32 => Bools)     public bools;  // Boolean state of Loan
    mapping (bytes32 => bytes32)   public fundi;  // Mapping of Loan Index to Fund Index
    mapping (bytes32 => ERC20)     public tokes;  // Mapping of Loan index to Token contract
    mapping (bytes32 => uint256)   public backs;  // Amount paid back in a Loan
    mapping (bytes32 => uint256)   public asaex;  // All Auction expiration
    uint256                        public loani;  // Current Loan Index

    mapping (address => bool)      public tokas;  // Is ERC20 Token Approved

    ERC20 public token; // ERC20 Debt Stablecoin

    address deployer;

    struct Loan {
    	address bor;        // Address Borrower
        address lend;       // Address Lender
        address agent;      // Optional Address automated agent
        uint256 born;       // Created At
        uint256 loex;       // Loan Expiration
        uint256 prin;       // Principal
        uint256 lint;       // Interest
        uint256 lpen;       // Liquidation Penalty
        uint256 lfee;       // Optional fee paid to auto if address not 0x0
        uint256 col;        // Collateral
        uint256 rat;        // Liquidation Ratio
        bytes   bpubk;      // Borrower PubKey
        bytes   lpubk;      // Lender PubKey
    }

    struct Sechs {
    	bytes32    sechA1;  // Secret Hash A1
    	bytes32[3] sechAS;  // Secret Hashes A2, A3, A4
    	bytes32    sechB1;  // Secret Hash B1
    	bytes32[3] sechBS;  // Secret Hashes B2, B3, B4
    	bytes32    sechC1;  // Secret Hash C1
    	bytes32[3] sechCS;  // Secret Hashes C2, C3, C4
    	bool       set;     // Secret Hashes set
    }

    struct Bools {
    	bool pushed;        // Loan Funded
    	bool marked;        // Collateral Marked as Locked
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

    function lint(bytes32 loan)   public view returns (uint256) {
        return loans[loan].lint;
    }

    function lfee(bytes32 loan)   public view returns (uint256) {
        return loans[loan].lfee;
    }

    function lpen(bytes32 loan)   public view returns (uint256) {
        return loans[loan].lpen;
    }

    function col(bytes32 loan)    public view returns (uint256) {
        return loans[loan].col;
    }

    function back(bytes32 loan)   public view returns (uint256) { // Amount paid back for loan
        return backs[loan];
    }

    function rat(bytes32 loan)    public view returns (uint256) {
        return loans[loan].rat;
    }

    function lent(bytes32 loan)   public view returns (uint256) { // Amount lent by Lender
        return add(prin(loan), lint(loan));
    }

    function lentb(bytes32 loan)  public view returns (uint256) { // Amount lent by lender minus amount paid back
        return sub(lent(loan), back(loan));
    }

    function owed(bytes32 loan)   public view returns (uint256) { // Amount owed
        return add(lent(loan), lfee(loan));
    }

    function owedb(bytes32 loan)  public view returns (uint256) { // Amount owed minus amount paid back
        return sub(owed(loan), back(loan));
    }

    function dedu(bytes32 loan)   public view returns (uint256) { // Deductible amount from collateral
        return add(owed(loan), lpen(loan));
    }

    function dedub(bytes32 loan)  public view returns (uint256) { // Deductible amount from collateral minus amount paid back
        return sub(dedu(loan), back(loan));
    }

    function pushed(bytes32 loan) public view returns (bool) {
        return bools[loan].pushed;
    }

    function marked(bytes32 loan) public view returns (bool) {
        return bools[loan].marked;
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
        return rmul(sub(prin(loan), back(loan)), rat(loan));
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
    
    function open(                   // Create new Loan
        uint256             loex_,   // Loan Expiration
        address[3] calldata usrs_,   // Borrower, Lender, Optional Automated Agent Addresses
        uint256[6] calldata vals_,   // Principal, Interest, Liquidation Penalty, Optional Automation Fee, Collaateral Amount, Liquidation Ratio
        bytes32             fundi_   // Optional Fund Index
    ) external returns (bytes32 loan) {
        loani = add(loani, 1);
        loan = bytes32(loani);
        loans[loan].born   = now;
        loans[loan].loex   = loex_;
        loans[loan].bor    = usrs_[0];
        loans[loan].lend   = usrs_[1];
        loans[loan].agent  = usrs_[2];
        loans[loan].prin   = vals_[0];
        loans[loan].lint   = vals_[1];
        loans[loan].lpen   = vals_[2];
        loans[loan].lfee   = vals_[3];
        loans[loan].col    = vals_[4];
        loans[loan].rat    = vals_[5];
        fundi[loan]        = fundi_;
        sechs[loan].set    = false;
    }

    function setSechs(             // Set Secret Hashes for Loan
    	bytes32           loan,    // Loan index
	bytes32[4] calldata bsechs,  // Borrower Secret Hashes
	bytes32[4] calldata lsechs,  // Lender Secret Hashes
	bytes32[4] calldata asechs,  // Agent Secret Hashes
		bytes      calldata bpubk_,  // Borrower Pubkey
        bytes      calldata lpubk_   // Lender Pubkey
	) external returns (bool) {
		require(!sechs[loan].set);
		require(msg.sender == loans[loan].bor || msg.sender == loans[loan].lend || msg.sender == address(funds));
		sechs[loan].sechA1 = bsechs[0];
		sechs[loan].sechAS = [ bsechs[1], bsechs[2], bsechs[3] ];
		sechs[loan].sechB1 = lsechs[0];
		sechs[loan].sechBS = [ lsechs[1], lsechs[2], lsechs[3] ];
		sechs[loan].sechC1 = asechs[0];
		sechs[loan].sechCS = [ asechs[1], asechs[2], asechs[3] ];
		loans[loan].bpubk  = bpubk_;
		loans[loan].lpubk  = lpubk_;
        sechs[loan].set    = true;
	}

	function push(bytes32 loan) external { // Fund Loan
		require(sechs[loan].set);
    	require(bools[loan].pushed == false);
    	require(token.transferFrom(msg.sender, address(this), prin(loan)));
    	bools[loan].pushed = true;
    }

    function mark(bytes32 loan) external { // Mark Collateral as locked
    	require(bools[loan].pushed == true);
    	require(loans[loan].lend   == msg.sender);
    	require(now                <= apex(loan));
    	bools[loan].marked = true;
    }

    function take(bytes32 loan, bytes32 secA1) external { // Withdraw
    	require(!off(loan));
    	require(bools[loan].pushed == true);
    	require(bools[loan].marked == true);
    	require(sha256(abi.encodePacked(secA1)) == sechs[loan].sechA1);
    	require(token.transfer(loans[loan].bor, prin(loan)));
    	bools[loan].taken = true;
    }

    function pay(bytes32 loan, uint256 amt) external { // Payback Loan
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

    function unpay(bytes32 loan) external { // Refund payback
    	require(!off(loan));
        require(!sale(loan));
    	require(now              >  acex(loan));
    	require(bools[loan].paid == true);
    	require(msg.sender       == loans[loan].bor);
        bools[loan].off = true;
    	require(token.transfer(loans[loan].bor, owed(loan)));
    }

    function pull(bytes32 loan, bytes32 sec) external {
        pull(loan, sec, true); // Default to true for returning funds to Fund
    }

    function pull(bytes32 loan, bytes32 sec, bool fund) public { // Accept or Cancel // Bool fund set true if lender wants fund to return to fund
        require(!off(loan));
        require(bools[loan].taken == false || bools[loan].paid == true);
        require(msg.sender == loans[loan].lend || msg.sender == loans[loan].agent);
        require(sha256(abi.encodePacked(sec)) == sechs[loan].sechB1 || sha256(abi.encodePacked(sec)) == sechs[loan].sechC1);
        require(now                             <= acex(loan));
        require(bools[loan].sale                == false);
        bools[loan].off = true;
        if (bools[loan].taken == false) {
            require(token.transfer(loans[loan].lend, loans[loan].prin));
        } else if (bools[loan].taken == true) {
            if (fundi[loan] == bytes32(0) || !fund) {
                require(token.transfer(loans[loan].lend, lent(loan)));
            } else {
                funds.push(fundi[loan], lent(loan));
            }
            require(token.transfer(loans[loan].agent, lfee(loan)));
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
        Sechs storage h = sechs[loan];
        uint256 i = sales.next(loan);
		sale = sales.open(loan, loans[loan].bor, loans[loan].lend, loans[loan].agent, h.sechAS[i], h.sechBS[i], h.sechCS[i]);
        if (bools[loan].sale == false) { require(token.transfer(address(sales), back(loan))); }
		bools[loan].sale = true;
    }
}
