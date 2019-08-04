import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

import './Loans.sol';
import './Medianizer.sol';
import './DSMath.sol';

pragma solidity ^0.5.8;

contract Sales is DSMath { // Auctions
	Loans loans;
	Medianizer med;

    uint256 public constant SALEX = 3600;                         // Sales Expiration
    uint256 public constant SWAEX = 7200;                         // Swap Expiration
    uint256 public constant SETEX = 14400;                        // Settlement Expiration
    uint256 public constant MINBI = 1005000000000000000000000000; // Minimum Bid Increment in RAY

	address public deployer; // Only the Loans contract can edit data

	mapping (bytes32 => Sale)       public sales; // Auctions
	mapping (bytes32 => Sig)        public bsigs; // Borrower Signatures
	mapping (bytes32 => Sig)        public lsigs; // Lender Signatures
	mapping (bytes32 => Sig)        public asigs; // Lender Signatures
	mapping (bytes32 => Sech)       public sechs; // Auction Secret Hashes
    uint256                         public salei; // Auction Index

    mapping (bytes32 => bytes32[])  public salel; // Loan Auctions (find by loani)

    ERC20 public token;

    struct Sale {
        bytes32    loani;  // Loan Index
        uint256    bid;    // Current Bid
        address    bidr;   // Bidder
        address    bor;    // Borrower
        address    lend;   // Lender
        address    agent;  // Optional Automated Agent
        uint256    born;   // Created At
        bytes20    pbkh;   // Bidder PubKey Hash
        bool       set;    // Sale at index opened
        bool       taken;  // Winning bid accepted
        bool       off;
    }

    struct Sig {
        bytes      rsig;  // Borrower Refundable Signature
        bytes      ssig;  // Borrower Seizable Signature
        bytes      rbsig; // Borrower Refundable Back Signature
        bytes      sbsig; // Borrower Seizable Back Signature
    }

    struct Sech {
        bytes32    sechA; // Secret Hash A
        bytes32    secA;  // Secret A
        bytes32    sechB; // Secret Hash B
        bytes32    secB;  // Secret B
        bytes32    sechC; // Secret Hash C
        bytes32    secC;  // Secret C
        bytes32    sechD; // Secret Hash D
        bytes32    secD;  // Secret D
    }

    function bid(bytes32 sale) public returns (uint256) {
        return sales[sale].bid;
    }

    function bidr(bytes32 sale) public returns (address) {
        return sales[sale].bidr;
    }

    function bor(bytes32 sale) public returns (address) {
        return sales[sale].bor;
    }

    function lend(bytes32 sale) public returns (address) {
        return sales[sale].lend;
    }

    function agent(bytes32 sale) public returns (address) {
        return sales[sale].agent;
    }

    function salex(bytes32 sale) public returns (uint256) {
        return sales[sale].born + SALEX;
    }

    function swaex(bytes32 sale) public returns (uint256) {
        return sales[sale].born + SALEX + SWAEX;
    }

    function setex(bytes32 sale) public returns (uint256) {
        return sales[sale].born + SALEX + SETEX;
    }

    function pbkh(bytes32 sale) public returns (bytes20) {
        return sales[sale].pbkh;
    }

    function taken(bytes32 sale) public returns (bool) {
        return sales[sale].taken;
    }

    function off(bytes32 sale) public returns (bool) {
        return sales[sale].off;
    }

    function sechA(bytes32 sale) public returns (bytes32) {
        return sechs[sale].sechA;
    }

    function secA(bytes32 sale) public returns (bytes32) {
        return sechs[sale].secA;
    }

    function sechB(bytes32 sale) public returns (bytes32) {
        return sechs[sale].sechB;
    }

    function secB(bytes32 sale) public returns (bytes32) {
        return sechs[sale].secB;
    }

    function sechC(bytes32 sale) public returns (bytes32) {
        return sechs[sale].sechC;
    }

    function secC(bytes32 sale) public returns (bytes32) {
        return sechs[sale].secC;
    }

    function sechD(bytes32 sale) public returns (bytes32) {
        return sechs[sale].sechD;
    }

    function secD(bytes32 sale) public returns (bytes32) {
        return sechs[sale].secD;
    }

    constructor (Loans loans_, Medianizer med_, ERC20 token_) public {
    	deployer = address(loans_);
    	loans    = loans_;
    	med      = med_;
        token    = token_;
    }

    function next(bytes32 loan) public view returns (uint256) {
    	return salel[loan].length;
    }

    function create(
    	bytes32 loani, // Loan Index
    	address bor,   // Address Borrower
    	address lend,  // Address Lender
        address agent, // Optional Address automated agent
    	bytes32 sechA, // Secret Hash A
    	bytes32 sechB, // Secret Hash B
    	bytes32 sechC // Secret Hash C
	) external returns(bytes32 sale) {
    	require(msg.sender == deployer);
    	salei = add(salei, 1);
        sale = bytes32(salei);
        sales[sale].loani = loani;
        sales[sale].bor   = bor;
        sales[sale].lend  = lend;
        sales[sale].agent = agent;
        sales[sale].born  = now;
        sales[sale].set   = true;
        sechs[sale].sechA = sechA;
        sechs[sale].sechB = sechB;
        sechs[sale].sechC = sechC;
        salel[loani].push(sale);
    }

    function push(     // Bid on Collateral
    	bytes32 sale,  // Auction Index
    	uint256 amt,   // Bid Amount
    	bytes32 sech,  // Secret Hash
    	bytes20 pbkh   // PubKeyHash
	) external {
        require(msg.sender != bor(sale) && msg.sender != lend(sale));
		require(sales[sale].set);
	require(now < salex(sale));
    	require(amt > sales[sale].bid);
    	require(token.balanceOf(msg.sender) >= amt);
    	if (sales[sale].bid > 0) {
		require(amt > rmul(sales[sale].bid, MINBI)); // Make sure next bid is at least 0.5% more than the last bid
    	}

    	require(token.transferFrom(msg.sender, address(this), amt));
    	if (sales[sale].bid > 0) {
    		require(token.transfer(sales[sale].bidr, sales[sale].bid));
    	}
    	sales[sale].bidr = msg.sender;
    	sales[sale].bid  = amt;
    	sechs[sale].sechD = sech;
    	sales[sale].pbkh = pbkh;
	}

	function sign(           // Provide Signature to move collateral to collateral swap
		bytes32      sale,   // Auction Index
		bytes calldata rsig,   // Refundable Signature
		bytes calldata ssig,   // Seizable Signature
		bytes calldata rbsig,  // Refundable Back Signature
		bytes calldata sbsig   // Seizable Back Signataure
	) external {
		require(sales[sale].set);
		require(now < setex(sale));
		if (msg.sender == sales[sale].bor) {
			bsigs[sale].rsig  = rsig;
			bsigs[sale].ssig  = ssig;
			bsigs[sale].rbsig = rbsig;
			bsigs[sale].sbsig = sbsig;
		} else if (msg.sender == sales[sale].lend) {
			lsigs[sale].rsig  = rsig;
			lsigs[sale].ssig  = ssig;
			lsigs[sale].rbsig = rbsig;
			lsigs[sale].sbsig = sbsig;
		} else if (msg.sender == sales[sale].agent) {
			asigs[sale].rsig  = rsig;
			asigs[sale].ssig  = ssig;
			asigs[sale].rbsig = rbsig;
			asigs[sale].sbsig = sbsig;
		} else {
			revert();
		}
	}

	function sec(bytes32 sale, bytes32 sec_) external { // Provide Secret
		require(sales[sale].set);
		if      (sha256(abi.encodePacked(sec_)) == sechs[sale].sechA) { sechs[sale].secA = sec_; }
        else if (sha256(abi.encodePacked(sec_)) == sechs[sale].sechB) { sechs[sale].secB = sec_; }
        else if (sha256(abi.encodePacked(sec_)) == sechs[sale].sechC) { sechs[sale].secC = sec_; }
        else if (sha256(abi.encodePacked(sec_)) == sechs[sale].sechD) { sechs[sale].secD = sec_; }
        else                                                          { revert(); }
	}

	function hasSecs(bytes32 sale) public view returns (bool) { // 2 of 3 secrets
		uint8 secs = 0;
		if (sha256(abi.encodePacked(sechs[sale].secA)) == sechs[sale].sechA) { secs = secs + 1; }
		if (sha256(abi.encodePacked(sechs[sale].secB)) == sechs[sale].sechB) { secs = secs + 1; }
		if (sha256(abi.encodePacked(sechs[sale].secC)) == sechs[sale].sechC) { secs = secs + 1; }
		return (secs >= 2);
	}

	function take(bytes32 sale) external { // Withdraw Bid (Accept Bid and disperse funds to rightful parties)
        require(!taken(sale));
        require(!off(sale));
		require(now > salex(sale));
		require(hasSecs(sale));
		require(sha256(abi.encodePacked(sechs[sale].secD)) == sechs[sale].sechD);
        sales[sale].taken = true;

        uint256 available = add(sales[sale].bid, loans.back(sales[sale].loani));
        uint256 amount = min(available, loans.lent(sales[sale].loani));

        require(token.transfer(sales[sale].lend, amount));
        available = sub(available, amount);

        if (available >= add(loans.fee(sales[sale].loani), loans.lpen(sales[sale].loani))) {
            if (agent(sale) != address(0)) {
                require(token.transfer(sales[sale].agent, loans.fee(sales[sale].loani)));
            }
            require(token.approve(address(med), loans.lpen(sales[sale].loani)));
            med.push(loans.lpen(sales[sale].loani), token);
            available = sub(available, add(loans.fee(sales[sale].loani), loans.lpen(sales[sale].loani)));
        } else if (available > 0) {
            require(token.approve(address(med), available));
            med.push(available, token);
            available = 0;
        }

        if (available > 0) { require(token.transfer(sales[sale].bor, available)); }
	}

	function unpush(bytes32 sale) external { // Refund Bid
        require(!taken(sale));
        require(!off(sale));
		require(now > setex(sale));
		require(sales[sale].bid > 0);
        sales[sale].off = true;
		require(token.transfer(sales[sale].bidr, sales[sale].bid));
        if (next(sales[sale].loani) == 3) {
            require(token.transfer(sales[sale].bor, loans.back(sales[sale].loani)));
        }
	}
}