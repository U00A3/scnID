// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {RedbellyEligibility} from "../gate/RedbellyEligibility.sol";

/// @title StakeVault
/// @notice Checkpointed escrow for native RBNT. Gives the stake chamber its voting weight.
///
/// @dev RBNT is the native coin, so there is no ERC-20 with checkpoints to read. The
///      current Snapshot space adds native balance, wRBNT
///      (0x6ed1F491e2d31536D6561f6bdB2AdC8F092a6076) and two staking contracts. None of
///      these can be read at a past block from inside the EVM. Reading them at vote time
///      would let someone borrow coins, vote and repay in the same block.
///
///      Stake is escrowed here instead and checkpointed by block. A proposal fixes its
///      snapshot block when it is created and only stake already in the vault at that
///      block counts.
///
///      Weight is the escrowed amount, with no square root or curve. With
///      w(x) = x^alpha, a holder who splits X across n wallets ends up with
///      n^(1-alpha) * X^alpha. That factor is 1 for every n only when alpha = 1.
///      Quadratic voting is alpha = 0.5 and gives 10^0.5 = 3.16 times the weight at ten
///      wallets, which rewards the splitting this chain allows and cannot detect.
///
///      Equal weighting belongs in the person chamber, where it is safe because that
///      chamber counts registered people and not addresses.
contract StakeVault {
    using Checkpoints for Checkpoints.Trace208;

    RedbellyEligibility public immutable eligibility;

    mapping(address => Checkpoints.Trace208) private _stake;
    Checkpoints.Trace208 private _total;

    /// @notice Delay between asking to withdraw and being able to take the funds.
    /// @dev The snapshot already stops flash loan votes. The delay is there to make short
    ///      term vote renting less attractive, since the capital has to sit idle for the
    ///      whole period after it stops counting.
    uint64 public immutable unbondingPeriod;

    struct Unbonding {
        uint208 amount;
        uint64 readyAt;
    }

    mapping(address => Unbonding) public unbonding;

    event Deposited(address indexed account, uint256 amount, uint256 newStake);
    event UnbondStarted(address indexed account, uint256 amount, uint64 readyAt);
    event Withdrawn(address indexed account, uint256 amount);

    error NotEligible(address account);
    error ZeroAmount();
    error InsufficientStake(uint256 have, uint256 want);
    error NothingUnbonding();
    error NotReady(uint64 readyAt);
    error UnbondingInProgress();
    error TransferFailed();
    error FutureLookup();

    constructor(address eligibility_, uint64 unbondingPeriod_) {
        eligibility = RedbellyEligibility(eligibility_);
        unbondingPeriod = unbondingPeriod_;
    }

    /// @notice Escrow native RBNT. It counts as stake chamber weight from the next block.
    /// @dev Only permissioned addresses can deposit, since the network won't transact
    ///      with anyone else anyway.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        if (!eligibility.isPermissioned(msg.sender)) revert NotEligible(msg.sender);

        uint208 amount = _toUint208(msg.value);
        (, uint208 newStake) = _stake[msg.sender].push(_clock(), _latest(_stake[msg.sender]) + amount);
        _total.push(_clock(), _latest(_total) + amount);

        emit Deposited(msg.sender, msg.value, newStake);
    }

    /// @notice Start withdrawing `amount`. The weight is removed straight away.
    /// @dev Weight goes when the request is made and not when the funds are claimed.
    ///      Otherwise someone could queue an exit and keep voting until it completes.
    function startUnbond(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (unbonding[msg.sender].amount != 0) revert UnbondingInProgress();

        uint208 current = _latest(_stake[msg.sender]);
        uint208 amt = _toUint208(amount);
        if (amt > current) revert InsufficientStake(current, amount);

        _stake[msg.sender].push(_clock(), current - amt);
        _total.push(_clock(), _latest(_total) - amt);

        uint64 readyAt = uint64(block.timestamp) + unbondingPeriod;
        unbonding[msg.sender] = Unbonding({amount: amt, readyAt: readyAt});
        emit UnbondStarted(msg.sender, amount, readyAt);
    }

    function withdraw() external {
        Unbonding memory u = unbonding[msg.sender];
        if (u.amount == 0) revert NothingUnbonding();
        if (block.timestamp < u.readyAt) revert NotReady(u.readyAt);

        delete unbonding[msg.sender];
        (bool ok,) = msg.sender.call{value: u.amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, u.amount);
    }

    // views

    function _clock() internal view returns (uint48) {
        return uint48(block.number);
    }

    function clock() external view returns (uint48) {
        return _clock();
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function stakeOf(address account) external view returns (uint256) {
        return _latest(_stake[account]);
    }

    function totalStaked() external view returns (uint256) {
        return _latest(_total);
    }

    /// @notice Stake chamber weight of `account` at `blockNumber`.
    function getPastStake(address account, uint256 blockNumber) external view returns (uint256) {
        if (blockNumber >= block.number) revert FutureLookup();
        return _stake[account].upperLookupRecent(uint48(blockNumber));
    }

    function getPastTotalStake(uint256 blockNumber) external view returns (uint256) {
        if (blockNumber >= block.number) revert FutureLookup();
        return _total.upperLookupRecent(uint48(blockNumber));
    }

    function _latest(Checkpoints.Trace208 storage t) private view returns (uint208) {
        return t.latest();
    }

    function _toUint208(uint256 x) private pure returns (uint208) {
        require(x <= type(uint208).max, "overflow");
        return uint208(x);
    }
}
