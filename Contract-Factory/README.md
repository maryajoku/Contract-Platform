# Contract Negotiation Platform

A comprehensive smart contract built on Stacks blockchain for creating, negotiating, and executing multi-party contracts with built-in payment escrow and revision management.

## Overview

The Contract Negotiation Platform enables users to create legally binding smart contracts that support:
- Multi-party negotiations with revision tracking
- Digital signature collection and verification
- Escrow payment management
- Automated contract execution
- Platform fee collection

## Features

### Core Functionality
- **Multi-party Contracts**: Support for up to 10 participants per contract
- **Flexible Signature Requirements**: Configurable threshold signatures (e.g., 3 out of 5 participants)
- **Contract States**: Full lifecycle management from draft to execution
- **Revision Management**: Track contract changes with approval workflows
- **Payment Escrow**: Secure STX token handling with automated distribution
- **Expiration Handling**: Time-based contract validity with automatic expiration

### Security Features
- Role-based access control
- Creator-only administrative functions
- Participant verification for all contract actions
- Platform fee protection with maximum limits
- Emergency pause functionality

## Contract States

The platform manages contracts through the following states:

1. **Draft** (`state-draft`): Initial contract creation
2. **Negotiation** (`state-negotiation`): Active revision and discussion phase
3. **Ready to Sign** (`state-ready-to-sign`): Terms finalized, awaiting signatures
4. **Partially Signed** (`state-partially-signed`): Some but not all required signatures collected
5. **Fully Signed** (`state-fully-signed`): All required signatures obtained
6. **Executed** (`state-executed`): Contract completed and payments distributed
7. **Cancelled** (`state-cancelled`): Contract terminated before completion
8. **Expired** (`state-expired`): Contract deadline passed

## Key Functions

### Contract Creation
```clarity
(create-contract title description participants required-signatures value duration terms-text)
```
Creates a new contract with specified parameters and participants.

### Contract Management
```clarity
(update-contract-state contract-id new-state)
(add-contract-revision contract-id new-terms change-description)
(cancel-contract contract-id)
```

### Signing Process
```clarity
(sign-contract contract-id signature-hash)
```
Allows participants to digitally sign the contract with cryptographic proof.

### Payment Operations
```clarity
(deposit-payment contract-id)
(execute-contract contract-id)
```
Handles escrow deposits and automated payment distribution upon execution.

## Usage Examples

### Creating a Simple Contract
```clarity
;; Create a 2-party service agreement requiring both signatures
(create-contract 
  "Website Development Agreement"
  "Development of corporate website with payment terms"
  (list 'SP123... 'SP456...)  ;; Client and developer addresses
  u2                          ;; Require both signatures
  u50000000                   ;; 50 STX contract value
  u604800                     ;; 7 days duration
  "Developer will create responsive website. Client pays 50 STX upon completion."
)
```

### Adding a Contract Revision
```clarity
;; Modify contract terms during negotiation
(add-contract-revision 
  u1                          ;; Contract ID
  "Updated terms: Developer will create responsive website with mobile app. Client pays 50 STX upon completion."
  "Added mobile app requirement"
)
```

### Signing and Executing
```clarity
;; Each participant signs the contract
(sign-contract u1 0x1234567890abcdef...)  ;; Participant 1 signature
(sign-contract u1 0xfedcba0987654321...)  ;; Participant 2 signature

;; Deposit payment (by participants)
(deposit-payment u1)

;; Execute contract (by creator after all conditions met)
(execute-contract u1)
```

## Data Structures

### Contract Data
- **Creator**: Contract originator address
- **Title/Description**: Human-readable contract information
- **Participants**: List of authorized contract parties (max 10)
- **Signature Requirements**: Minimum signatures needed for execution
- **Value**: STX amount held in escrow
- **Timestamps**: Creation, expiration, and execution deadlines
- **State**: Current contract lifecycle stage

### Participant Data
- **Signature Status**: Whether participant has signed current revision
- **Role**: Participant's role in the contract
- **Modification Rights**: Permission to propose revisions

## Platform Economics

### Fee Structure
- Default platform fee: 2.5% of contract value
- Configurable by platform administrator (max 10%)
- Fees collected upon successful contract execution

### Minimum Requirements
- Contract duration: Minimum 24 hours (86400 seconds)
- Participants: At least 1, maximum 10
- Signature threshold: At least 1, cannot exceed participant count

## Error Handling

The contract includes comprehensive error handling with descriptive error codes:

- **ERR-OWNER-ONLY** (100): Administrative functions restricted to deployer
- **ERR-NOT-FOUND** (101): Contract or data not found
- **ERR-UNAUTHORIZED-ACCESS** (102): User lacks required permissions
- **ERR-INVALID-STATE** (103): Operation not allowed in current contract state
- **ERR-ALREADY-SIGNED** (104): Participant already signed current revision
- **ERR-CONTRACT-EXPIRED** (106): Contract deadline has passed
- **ERR-INVALID-PARTICIPANT** (108): User not authorized for this contract

## Administrative Functions

Platform administrators can:
- Adjust platform fee percentage
- Modify minimum contract duration requirements
- Withdraw collected platform fees
- Emergency pause contracts if needed

## Security Considerations

1. **Access Control**: All functions verify caller permissions
2. **State Validation**: Contracts can only transition through valid states
3. **Signature Verification**: Cryptographic signatures prevent forgery
4. **Payment Protection**: Escrow system prevents premature fund release
5. **Expiration Handling**: Time-based restrictions prevent stale contract execution

## Integration

This contract can be integrated with:
- Web3 dApps for contract management interfaces
- Legal document systems for terms generation
- Payment processors for fiat-to-STX conversion
- Notification systems for signature reminders