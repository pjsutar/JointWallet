// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.4.22 <=0.8.30;

contract BankAccount {
    event Deposit(
        address indexed user, 
        uint256 indexed accountId, 
        uint256 value, 
        uint256 timestamp
    );
    
    event WithdrawalRequested(
        address indexed user, 
        uint256 indexed accountId, 
        uint256 indexed withdrawId, 
        uint256 amount, 
        uint256 timestamp
    );
    
    event Withdraw(uint256 indexed withdrawId, uint256 timestamp);

    event AccountCreated(address[] owners, uint256 indexed id, uint256 timestamp);

    struct WithdrawalRequest {
        address user;
        uint256 amount;
        uint256 approvals;
        mapping(address => bool) ownersApproved;
        bool approved;
    }

    struct Account {
        address[] owners;
        uint256 balance;
        mapping(uint256 => WithdrawalRequest) withdrawalRequests;
    }

    // Associate accounts with account IDs
    mapping(uint256 => Account) accounts;

    // Associate users with their accounts using account IDs
    mapping(address => uint256[]) userAccounts;

    uint256 nextAccountId;
    uint256 nextWithdrawId;

    modifier accountOwner(uint256 accountId) {
        // Check if the sender is account owner
        bool isOwner;
        for (uint256 idx; idx < accounts[accountId].owners.length; idx++) {
            if (accounts[accountId].owners[idx] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "You are not an owner of this account.");
        _;
    }

    modifier validOwners(address[] calldata owners) {
        // Check number of owners per account
        require(owners.length + 1 <= 4, "Each account can have a maximum of 4 owners.");

        // Check for duplicate owners
        for (uint256 i; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                revert("No duplicate owners are allowed.");
            }

            for (uint256 j = i + 1; j < owners.length; j++) {
                if (owners[i] == owners[j]) {
                    revert("No duplicate owners are allowed.");
                }
            }
        }

        _;
    }

    modifier sufficientBalance(uint256 accountId, uint256 amount) {
        // Check for sufficient balance
        require(accounts[accountId].balance >= amount, "Insufficient balance.");
        _;
    }

    modifier canApprove(uint256 accountId, uint256 withdrawId) {
        // Check if request is already approved
        require(
            !accounts[accountId].withdrawalRequests[withdrawId].approved,
            "This request is already approved."
        );

        // Ensure users are not approving their own request
        require(
            accounts[accountId].withdrawalRequests[withdrawId].user != msg.sender,
            "You can not approve this request."
        );

        // Check if users have already approved the request
        require(
            !accounts[accountId].withdrawalRequests[withdrawId].ownersApproved[msg.sender],
            "You have already approved this request."
        );

        // Check if necessary variables are uninitialized or deleted by already withdrawn request
        require(
            accounts[accountId].withdrawalRequests[withdrawId].user != address(0),
            "This request does not exist."
        );

        _;
    }

    modifier canWithdraw(uint256 accountId, uint256 withdrawId) {
        // Check if the request is approved
        require(accounts[accountId].withdrawalRequests[withdrawId].approved, "This request is not approved yet.");

        // Check if the withdrawing user has created the withdrawal request
        require(accounts[accountId].withdrawalRequests[withdrawId].user == msg.sender, "You did not create this request.");

        _;
    }

    function deposit(uint256 accountId) external payable accountOwner(accountId) {
        accounts[accountId].balance += msg.value;
    }

    function createAccount(address[] calldata otherOwners) external validOwners(otherOwners) {
        address[] memory owners = new address[] (otherOwners.length + 1);
        owners[otherOwners.length] = msg.sender;

        uint256 id = nextAccountId;

        for (uint256 idx; idx < owners.length; idx++) {
            if (idx < owners.length - 1) {
                owners[idx] = otherOwners[idx];
            }

            if (userAccounts[owners[idx]].length > 2) {
                revert("Each user can have a maximum of 3 accounts.");
            }
            userAccounts[owners[idx]].push(id);
        }

        accounts[id].owners = owners;
        nextAccountId++;
        emit AccountCreated(owners, id, block.timestamp);
    }

    function requestWithdrawal(uint256 accountId, uint256 amount) external accountOwner(accountId) sufficientBalance(accountId, amount) {
        uint256 id = nextWithdrawId;
        WithdrawalRequest storage request = accounts[accountId].withdrawalRequests[id];
        request.user = msg.sender;
        request.amount = amount;
        nextWithdrawId++;
        emit WithdrawalRequested(msg.sender, accountId, id, amount, block.timestamp);
    }

    function approveWithdrawal(uint256 accountId, uint256 withdrawId) external accountOwner(accountId) canApprove(accountId, withdrawId) {
        WithdrawalRequest storage request = accounts[accountId].withdrawalRequests[withdrawId];
        request.approvals++;
        request.ownersApproved[msg.sender] = true;

        if (request.approvals == accounts[accountId].owners.length - 1) {
            request.approved = true;
        }
    }

    function withdraw(uint256 accountId, uint256 withdrawId) external canWithdraw(accountId, withdrawId) {
        uint256 amount = accounts[accountId].withdrawalRequests[withdrawId].amount;
        
        // Check for sufficient balance again in case of multiple withdraws
        require(accounts[accountId].balance >= amount, "Insufficient balance.");
        accounts[accountId].balance -= amount;
        delete accounts[accountId].withdrawalRequests[withdrawId];

        (bool sent,) = payable(msg.sender).call{value: amount}("");
        require(sent);
        emit Withdraw(withdrawId, block.timestamp);
    }

    function getBalance(uint256 accountId) public view returns (uint256) {
        return accounts[accountId].balance;
    }

    function getOwners(uint256 accountId) public view returns (address[] memory) {
        return accounts[accountId].owners;
    }

    function getApprovals(uint256 accountId, uint256 withdrawId) public view returns (uint256) {
        return accounts[accountId].withdrawalRequests[withdrawId].approvals;
    }

    function getAccounts() public view returns (uint256[] memory) {
        return userAccounts[msg.sender];
    }

}