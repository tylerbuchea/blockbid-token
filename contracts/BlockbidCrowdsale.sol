pragma solidity ^0.4.11;

import 'zeppelin-solidity/contracts/crowdsale/Crowdsale.sol';
import './BlockbidMintableToken.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';

/**
 * @title CappedCrowdsale
 * @dev Extension of Crowdsale with a max amount of funds raised
 */
contract BlockbidCrowdsale is Crowdsale, Ownable {

  uint public goal;
  uint public cap;
  uint public earlybonus;
  uint public standardrate;
  uint public totalSupply;
  uint public icoEndTime;
  bool public goalReached = false;
  mapping(address => uint) public weiContributed;
  address[] public contributors;

  event LogClaimRefund(address _address, uint _value);

  function BlockbidCrowdsale(uint _goal, uint _cap, uint _startTime, uint _endTime, uint _icoEndTime, uint _rate, uint _earlyBonus, address _wallet)
  Crowdsale(_startTime, _endTime, _rate, _wallet) public {
    require(_cap > 0);
    require(_goal > 0);

    icoEndTime = _icoEndTime;
    standardrate = _rate;
    earlybonus = _earlyBonus;
    cap = _cap;
    goal = _goal;
  }

  // @return true if the transaction can buy tokens
  /*
  Added: - Must be under Cap
         - Requires user to send atleast 1 token's worth of ether
         - Needs to call updateRate() function to validate how much ether = 1 token
         -
  */

  function validPurchase() internal constant returns (bool) {
    updateRate();

    if (hasEnded() && !goalReached) {
      return false;
    }

    else {
      bool withinPeriod = (now >= startTime && now <= endTime);
      bool nonZeroPurchase = (msg.value >= 0.1 ether && msg.value <= 100 ether);
      bool withinCap = (token.totalSupply() <= cap);
      return withinPeriod && nonZeroPurchase && withinCap;
    }
  }

  // function that will determine how many tokens have been created
  function tokensPurchased() internal constant returns (uint) {
    return rate.mul(msg.value)/1 ether;
  }

  /*
    function will identify what period of crowdsale we are in and update
    the rate.
    Rates are lower (e.g. 1:360 instead of 1:300) early on
    to give early bird discounts
  */
  function updateRate() internal returns (bool) {

    uint weeklength = 604800;

    if (hasEnded()) {
      rate = 200;
    }

    else {
      if (now >= startTime.add(weeklength.mul(3))) {
        rate = standardrate;
      }
      else if (now >= startTime.add(weeklength.mul(2))) {
        rate = standardrate.add(earlybonus.div(3));
      }
      else if (now >= startTime.add(weeklength)) {
        rate = standardrate.add((earlybonus.mul(2).div(3)));
      }
      else {
        rate = standardrate.add(earlybonus);
      }
    }

    return true;
  }

  function buyTokens(address beneficiary) public payable {
    require(beneficiary != 0x0);

    // enables wallet to bypass valid purchase requirements
    if (msg.sender == wallet) {
      require(hasEnded());
      require(!goalReached);
    }

    else {
      require(validPurchase());
    }

    // update state
    weiRaised = weiRaised.add(msg.value);

    // if user already a contributor
    if (weiContributed[beneficiary] > 0) {
      weiContributed[beneficiary] = weiContributed[beneficiary].add(msg.value);
    }
    // new contributor
    else {
      weiContributed[beneficiary] = msg.value;
      contributors.push(beneficiary);
    }

    // update tokens for each individual
    token.mint(beneficiary, tokensPurchased());
    TokenPurchase(msg.sender, beneficiary, msg.value, tokensPurchased());
    token.mint(wallet, (tokensPurchased().div(4)));

    if (token.totalSupply() > goal) {
      goalReached = true;
    }

    // don't forward funds if wallet belongs to owner
    if (msg.sender != wallet) {
      forwardFunds();
    }
  }

  function getContributorsCount() public constant returns(uint) {
    return contributors.length;
  }

  // if crowdsale is unsuccessful, investors can claim refunds here
  function claimRefund() public returns (bool) {
    require(!goalReached);
    require(hasEnded());
    uint contributedAmt = weiContributed[msg.sender];
    require(contributedAmt > 0);
    weiContributed[msg.sender] = 0;
    msg.sender.transfer(contributedAmt);
    LogClaimRefund(msg.sender, contributedAmt);
    return true;
  }

  // @return true if crowdsale event has ended
  function hasEnded() public constant returns (bool) {
    return now >= icoEndTime;
  }

  // destroy contract and send all remaining ether back to wallet
  function kill() onlyOwner public {
    require(!goalReached);
    require(hasEnded());
    selfdestruct(wallet);
  }

  function createTokenContract() internal returns (MintableToken) {
    return new BlockbidMintableToken();
  }

}