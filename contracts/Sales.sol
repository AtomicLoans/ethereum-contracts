import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

import './Loans.sol';
import './Medianizer.sol';
import './DSMath.sol';

pragma solidity ^0.5.8;

contract Sales is DSMath { // Auctions
	Loans loans;
	Medianizer med;

    uint256 public constant SWAP_EXP = 7200;                      // Swap Expiration
    uint256 public constant SETTLEMENT_EXP = 14400;               // Settlement Expiration

	address public deployer; // Only the Loans contract can edit data

	mapping (bytes32 => Sale)       public sales;        // Auctions
	mapping (bytes32 => Sig)        public borrowerSigs; // Borrower Signatures
	mapping (bytes32 => Sig)        public lenderSigs;   // Lender Signatures
	mapping (bytes32 => Sig)        public agentSigs;    // Lender Signatures
	mapping (bytes32 => SecretHash) public secretHashes; // Auction Secret Hashes
    uint256                         public saleIndex;    // Auction Index

    mapping (bytes32 => bytes32[])  public saleIndexByLoan; // Loan Auctions (find by loanIndex)

    ERC20 public token;

    struct Sale {
        bytes32    loanIndex;   // Loan Index
        uint256    discountBuy; // Amount collateral was bought for at discount
        address    liquidator;  // Party who buys the collateral at a discount
        address    borrower;    // Borrower
        address    lender;      // Lender
        address    agent;       // Optional Automated Agent
        uint256    createdAt;   // Created At
        bytes20    pubKeyHash;  // Liquidator PubKey Hash
        bool       set;         // Sale at index opened
        bool       accepted;    // discountBuy accepted
        bool       off;
    }

    struct Sig {
        bytes refundableSig;  // Borrower Refundable Signature
        bytes seizableSig;  // Borrower Seizable Signature
    }

    struct SecretHash {
        bytes32 secretHashA; // Secret Hash A
        bytes32 secretA;     // Secret A
        bytes32 secretHashB; // Secret Hash B
        bytes32 secretB;     // Secret B
        bytes32 secretHashC; // Secret Hash C
        bytes32 secretC;     // Secret C
        bytes32 secretHashD; // Secret Hash D
        bytes32 secretD;     // Secret D
    }

    function discountBuy(bytes32 sale) public view returns (uint256) {
        return sales[sale].discountBuy;
    }

    function liquidator(bytes32 sale) public returns (address) {
        return sales[sale].liquidator;
    }

    function borrower(bytes32 sale) public returns (address) {
        return sales[sale].borrower;
    }

    function lender(bytes32 sale) public returns (address) {
        return sales[sale].lender;
    }

    function agent(bytes32 sale) public returns (address) {
        return sales[sale].agent;
    }

    function swapExpiration(bytes32 sale) public returns (uint256) {
        return sales[sale].createdAt + SWAP_EXP;
    }

    function settlementExpiration(bytes32 sale) public returns (uint256) {
        return sales[sale].createdAt + SETTLEMENT_EXP;
    }

    function pubKeyHash(bytes32 sale) public returns (bytes20) {
        return sales[sale].pubKeyHash;
    }

    function accepted(bytes32 sale) public returns (bool) {
        return sales[sale].accepted;
    }

    function off(bytes32 sale) public returns (bool) {
        return sales[sale].off;
    }

    function secretHashA(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretHashA;
    }

    function secretA(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretA;
    }

    function secretHashB(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretHashB;
    }

    function secretB(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretB;
    }

    function secretHashC(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretHashC;
    }

    function secretC(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretC;
    }

    function secretHashD(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretHashD;
    }

    function secretD(bytes32 sale) public returns (bytes32) {
        return secretHashes[sale].secretD;
    }

    constructor (Loans loans_, Medianizer med_, ERC20 token_) public {
    	deployer = address(loans_);
    	loans    = loans_;
    	med      = med_;
        token    = token_;
    }

    function next(bytes32 loan) public view returns (uint256) {
    	return saleIndexByLoan[loan].length;
    }

    function create(
    	bytes32 loanIndex,   // Loan Index
    	address borrower,    // Address Borrower
    	address lender,      // Address Lender
        address agent,       // Optional Address automated agent
        address liquidator,  // Liquidator address
    	bytes32 secretHashA, // Secret Hash A
    	bytes32 secretHashB, // Secret Hash B
    	bytes32 secretHashC, // Secret Hash C
        bytes32 secretHashD, // Secret Hash D
        bytes20 pubKeyHash   // Liquidator PubKeyHash
	) external returns(bytes32 sale) {
    	require(msg.sender == deployer);
    	saleIndex = add(saleIndex, 1);
        sale = bytes32(saleIndex);
        sales[sale].loanIndex   = loanIndex;
        sales[sale].borrower    = borrower;
        sales[sale].lender      = lender;
        sales[sale].agent       = agent;
        sales[sale].liquidator  = liquidator;
        sales[sale].createdAt   = now;
        sales[sale].pubKeyHash  = pubKeyHash;
        sales[sale].discountBuy = loans.discountCollateralValue(loanIndex);
        sales[sale].set         = true;
        secretHashes[sale].secretHashA = secretHashA;
        secretHashes[sale].secretHashB = secretHashB;
        secretHashes[sale].secretHashC = secretHashC;
        secretHashes[sale].secretHashD = secretHashD;
        saleIndexByLoan[loanIndex].push(sale);
    }

	function provideSig(              // Provide Signature to move collateral to collateral swap
		bytes32        sale,          // Auction Index
		bytes calldata refundableSig, // Refundable Signature
		bytes calldata seizableSig    // Seizable Signature
	) external {
		require(sales[sale].set);
		require(now < settlementExpiration(sale));
		if (msg.sender == sales[sale].borrower) {
			borrowerSigs[sale].refundableSig = refundableSig;
			borrowerSigs[sale].seizableSig   = seizableSig;
		} else if (msg.sender == sales[sale].lender) {
			lenderSigs[sale].refundableSig = refundableSig;
			lenderSigs[sale].seizableSig   = seizableSig;
		} else if (msg.sender == sales[sale].agent) {
			agentSigs[sale].refundableSig = refundableSig;
			agentSigs[sale].seizableSig   = seizableSig;
		} else {
			revert();
		}
	}

	function provideSecret(bytes32 sale, bytes32 secret_) external { // Provide Secret
		require(sales[sale].set);
		if      (sha256(abi.encodePacked(secret_)) == secretHashes[sale].secretHashA) { secretHashes[sale].secretA = secret_; }
        else if (sha256(abi.encodePacked(secret_)) == secretHashes[sale].secretHashB) { secretHashes[sale].secretB = secret_; }
        else if (sha256(abi.encodePacked(secret_)) == secretHashes[sale].secretHashC) { secretHashes[sale].secretC = secret_; }
        else if (sha256(abi.encodePacked(secret_)) == secretHashes[sale].secretHashD) { secretHashes[sale].secretD = secret_; }
        else                                                                          { revert(); }
	}

	function hasSecrets(bytes32 sale) public view returns (bool) { // 2 of 3 secrets
		uint8 numCorrectSecrets = 0;
		if (sha256(abi.encodePacked(secretHashes[sale].secretA)) == secretHashes[sale].secretHashA) { numCorrectSecrets = numCorrectSecrets + 1; }
		if (sha256(abi.encodePacked(secretHashes[sale].secretB)) == secretHashes[sale].secretHashB) { numCorrectSecrets = numCorrectSecrets + 1; }
		if (sha256(abi.encodePacked(secretHashes[sale].secretC)) == secretHashes[sale].secretHashC) { numCorrectSecrets = numCorrectSecrets + 1; }
		return (numCorrectSecrets >= 2);
	}

	function accept(bytes32 sale) external { // Withdraw DiscountBuy (Accept DiscountBuy and disperse funds to rightful parties)
        require(!accepted(sale));
        require(!off(sale));
		require(hasSecrets(sale));
		require(sha256(abi.encodePacked(secretHashes[sale].secretD)) == secretHashes[sale].secretHashD);
        sales[sale].accepted = true;

        uint256 available = add(sales[sale].discountBuy, loans.repaid(sales[sale].loanIndex));
        uint256 amount = min(available, loans.owedToLender(sales[sale].loanIndex));

        require(token.transfer(sales[sale].lender, amount));
        available = sub(available, amount);

        if (available >= add(loans.fee(sales[sale].loanIndex), loans.penalty(sales[sale].loanIndex))) {
            if (agent(sale) != address(0)) {
                require(token.transfer(sales[sale].agent, loans.fee(sales[sale].loanIndex)));
            }
            require(token.approve(address(med), loans.penalty(sales[sale].loanIndex)));
            med.push(loans.penalty(sales[sale].loanIndex), token);
            available = sub(available, add(loans.fee(sales[sale].loanIndex), loans.penalty(sales[sale].loanIndex)));
        } else if (available > 0) {
            require(token.approve(address(med), available));
            med.push(available, token);
            available = 0;
        }

        if (available > 0) { require(token.transfer(sales[sale].borrower, available)); }
	}

	function refund(bytes32 sale) external { // Refund DiscountBuy
        require(!accepted(sale));
        require(!off(sale));
		require(now > settlementExpiration(sale));
		require(sales[sale].discountBuy > 0);
        sales[sale].off = true;
		require(token.transfer(sales[sale].liquidator, sales[sale].discountBuy));
        if (next(sales[sale].loanIndex) == 3) {
            require(token.transfer(sales[sale].borrower, loans.repaid(sales[sale].loanIndex)));
        }
	}
}