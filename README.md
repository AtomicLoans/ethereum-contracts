
# Atomic Loans Ethereum Contracts

[![Build Status](https://travis-ci.org/AtomicLoans/atomicloans-eth-contracts.svg?branch=master)](https://travis-ci.org/AtomicLoans/atomicloans-eth-contracts)
[![Coverage Status](https://coveralls.io/repos/github/AtomicLoans/atomicloans-eth-contracts/badge.svg)](https://coveralls.io/github/AtomicLoans/atomicloans-eth-contracts)
[![MIT License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](./LICENSE.md)
[![Telegram](https://img.shields.io/badge/chat-on%20telegram-blue.svg)](https://t.me/Atomic_Loans)
[![Greenkeeper badge](https://badges.greenkeeper.io/AtomicLoans/atomicloans-eth-contracts.svg)](https://greenkeeper.io/)

Loan Contracts

## How to run

### Requirements

- Git
- Node.Js
- Truffle

Steps:

```
git clone https://github.com/AtomicLoans/ethereum-contracts.git
cd ethereum-contracts
npm install
```

Now run the tests:

`truffle test`

## License

MIT

## Glossary

### `Fund`
```
Actions:

   create            create new loan fund
   deposit           post additional toks to fund
   generate          generate secret hashes for loan fund
   request           request loan from fund
   withdraw          withdraw unused funds from the loan fund
   update            update loan fund request details


Getters:

   agent               optional automated agent
   balance             amount of unused funds deposited in loan fund
   lender              loan fund owner
   fee                 optional automation fee
   interest            interest rate
   liquidationRatio    liquidation ratio
   maxLoanAmt          max loan amount
   maxLoanDur          max loan duration
   minLoanAmt          min loan amount
   minLoanDur          min loan duration
   penalty             liquidation penalty
   token               debt token


Vars:

   fundIndex           get the last fund id
   pubKeys             address pubkeys
   secretHashes        address secret hashes
   secretHashIndex     address secret hash index

```


### `Loan`
```
Actions:

   accept                accept loan and remove funds
   approve               approve locking of collateral
   cancel                cancel loan and remove funds
   create                create new loan
   fund                  fund loan
   liquidate             auction loan collateral in case of liquidation or default
   refund                refund debt repayment 
   repay                 repay debt
   setSecretHashes       set secret hashes for loan
   withdraw              withdraw loan


Getters:

   acceptExpiration      acceptance expirataion
   agent                 optional automation agent address
   approveExpiration     approval expiraation
   biddingExpiration     bidding expiration
   borrower              borrower address
   collateral            collateral amount
   collateralValue       current collateral value
   fee                   optional fee paid to automator agent if address not 0x0
   interest              loan interest rate
   lender                lender address
   liquidationRatio      liquidation ratio
   minCollateralValue    minimum collateral value to be safe
   off                   loan repayment accepted or loan cancelled
   owedForLiquidation    deductible amount from collateral in the case of liquidation
   owedForLoan           prin + interest + fee
   owedToLender          amount lent by lender
   penalty               liquidation penalty in case not safe or defaulted
   principal             loan principal
   pushed                loan funded
   repaid                amount paid back for loan
   safe                  loan is safe from liquidation


Vars:

   fundIndex             loan fund index
   loanIndex             get the last loan id
   repayments            amount of loan paid back
   
```

### `Sales`
```
Actions:

   accept                withdraw bid (accept bid and disperse funds to rightful parties)
   create                create new auction (can only be called by loan)
   offer                 bid on collateral
   provideSecret         provide secret
   provideSig            provide signature to move collateral to collateral swap
   refund                refund bid


Getters:

   accepted              winning bid accepted
   agent                 optional automated agent
   agentSigs             agent refundable and seizable signatures
   bid                   current bid
   bidder                address current bidder
   borrower              address borrower
   borrowerSigs          borrower refundable and seizable signatures
   hasSecrets            2 of 3 secrets from bor, lend, and agent are correct
   lender                address lender
   lenderSigs            lender refundable and seizable signatures
   next                  get the last auction id by loan
   pubKeyHash            bidder pubkeyhash
   salesExpiration       sales expiration
   secretA               Secret A
   secretB               Secret B
   secretC               Secret C
   secretD               Secret D
   secretHashA           Secret Hash A
   secretHashB           Secret Hash B
   secretHashC           Secret Hash C
   secretHashD           Secret Hash D
   settlementExpiration  auction settlement expiration
   
   
Vars:

   saleIndexByLoan       loan auction (find by loanIndex)

```

