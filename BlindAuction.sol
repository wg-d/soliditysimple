// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;
contract BlindAuction {
    struct Bid {
        bytes32 blindedBid;
        uint deposit;
    }   
    address payable public beneficiary;
    uint public biddingEnd;
    uint public revealEnd;
    bool public ended;
    mapping(address => Bid[]) public bids;
    address public highestBidder;
    uint public highestBid;
    // Allowed withdrawals of previous bids
    mapping(address => uint) pendingReturns;
    event AuctionEnded(address winner, uint highestBid);
    // Errors that describe failures.
    /// The function has been called too early.
    /// Try again at ‘time‘.
    error TooEarly(uint time);
    /// The function has been called too late.
    /// It cannot be called after ‘time‘.
    error TooLate(uint time);
    /// The function auctionEnd has already been called.
    error AuctionEndAlreadyCalled();
    // Modifiers are a convenient way to validate inputs to
    // functions. ‘onlyBefore‘ is applied to ‘bid‘ below:
    // The new function body is the modifier’s body where
    // ‘_‘ is replaced by the old function body.
    modifier onlyBefore(uint _time) {
        if (block.timestamp >= _time) revert TooLate(_time);
        _;
    }
    modifier onlyAfter(uint _time) {
        if (block.timestamp <= _time) revert TooEarly(_time);
        _;
    }
    constructor(
        uint _biddingTime,
        uint _revealTime,
        address payable _beneficiary
    ) {
        beneficiary = _beneficiary;
        biddingEnd = block.timestamp + _biddingTime;
        revealEnd = biddingEnd + _revealTime;
    }
    /// Place a blinded bid with ‘_blindedBid‘ =
    /// keccak256(abi.encodePacked(value, fake, secret)).
    /// The sent ether is only refunded if the bid is correctly
    /// revealed in the revealing phase. The bid is valid if the
    /// ether sent together with the bid is at least "value" and
    /// "fake" is not true. Setting "fake" to true and sending
    /// not the exact amount are ways to hide the real bid but
    /// still make the required deposit. The same address can
    /// place multiple bids.
    function bid(bytes32 _blindedBid)
    public
    payable
    onlyBefore(biddingEnd)
    {
        bids[msg.sender].push(Bid({
        blindedBid: _blindedBid,
        deposit: msg.value
        }));
    }
    /// Reveal your blinded bids. You will get a refund for all
    /// correctly blinded invalid bids and for all bids except for
    /// the totally highest.
    function reveal(
        uint[] memory _values,
        bool[] memory _fake,
        bytes32[] memory _secret
    )
    public
    onlyAfter(biddingEnd)
    onlyBefore(revealEnd)
    {
        uint length = bids[msg.sender].length;
        require(_values.length == length);
        require(_fake.length == length);
        require(_secret.length == length);
        uint refund;
        for (uint i = 0; i < length; i++) {
            Bid storage bidToCheck = bids[msg.sender][i];
            (uint value, bool fake, bytes32 secret) =
            (_values[i], _fake[i], _secret[i]);
            if (bidToCheck.blindedBid != keccak256(abi.encodePacked(value, fake,secret))) {
            // Bid was not actually revealed.
            // Do not refund deposit.
            continue;
            }
            refund += bidToCheck.deposit;
            if (!fake && bidToCheck.deposit >= value) {
                if (placeBid(msg.sender, value))
                refund -= value;
            }
            // Make it impossible for the sender to re-claim
            // the same deposit.
            bidToCheck.blindedBid = bytes32(0);
        }
        payable(msg.sender).transfer(refund);
    }
    /// Withdraw a bid that was overbid.
    function withdraw() public {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
        // It is important to set this to zero because the recipient
        // can call this function again as part of the receiving call
        // before ‘transfer‘ returns (see the remark above about
        // conditions -> effects -> interaction).
        pendingReturns[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        }
    }
    /// End the auction and send the highest bid
    /// to the beneficiary.
    function auctionEnd()
    public
    onlyAfter(revealEnd)
    {
        if (ended) revert AuctionEndAlreadyCalled();
        emit AuctionEnded(highestBidder, highestBid);
        ended = true;
        beneficiary.transfer(highestBid);
    }
    // This is an "internal" function which means that it
    // can only be called from the contract itself (or from
    // derived contracts).
    function placeBid(address bidder, uint value) internal
    returns (bool success)
    {
        if (value <= highestBid) {
        return false;
    }
    if (highestBidder != address(0)) {
    // Refund the previously highest bidder.
        pendingReturns[highestBidder] += highestBid;
    }
    highestBid = value;
    highestBidder = bidder;
    return true;
    }
}