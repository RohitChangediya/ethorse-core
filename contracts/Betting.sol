pragma solidity ^0.4.10;
import "./lib/usingOraclize.sol";
import "./lib/SafeMath.sol";


contract Betting is usingOraclize {
    using SafeMath for uint256; //using safemath

    bytes32 coin_pointer; // variable to differentiate different callbacks
    bytes32 temp_ID; // temp variable to store oraclize IDs
    uint countdown=3; // variable to check if all prices are received
    address public owner; //owner address
    int public BTC_delta; //BTC delta value
    int public ETH_delta; //ETH delta value
    int public LTC_delta; //LTC delta value
    bytes32 public BTC=bytes32("BTC"); //32-bytes equivalent of BTC
    bytes32 public ETH=bytes32("ETH"); //32-bytes equivalent of ETH
    bytes32 public LTC=bytes32("LTC"); //32-bytes equivalent of LTC
    bool public betting_open=false; // boolean: check if betting is open
    bool public race_start=false; //boolean: check if race has started
    bool public race_end=false; //boolean: check if race has ended
    bool public voided_bet=false; //boolean: check if race has been voided
    uint kickStarter = 0; // ethers to kickcstart the oraclize queries
    uint public starting_time; // timestamp of when the race starts
    uint public betting_duration;
    uint public race_duration; // duration of the race
    uint public winningPoolTotal;

    struct bet_info{
        bytes32 horse; // coin on which amount is bet on
        uint amount; // amount bet by Bettor
    }
    struct coin_info{
        uint total; // total coin pool
        uint pre; // locking price
        uint post; // ending price
        uint count; // number of bets
        bool price_check; // boolean: differentiating pre and post prices
    }
    struct voter_info {
        uint bet_count; //number of bets
        bool rewarded; // boolean: check for double spending
        bet_info[] bets; //array of bets
    }

    mapping (bytes32 => bytes32) oraclizeIndex; // mapping oraclize IDs with coins
    mapping (bytes32 => coin_info) coinIndex; // mapping coins with pool information
    mapping (address => voter_info) voterIndex; // mapping voter address with Bettor information

    uint public total_reward; // total reward to be awarded
//    bytes32 public winner_horse; // winning coin
    mapping (bytes32 => bool) winner_horse;


    // tracking events
    event newOraclizeQuery(string description);
    event newPriceTicker(uint price);
    event Deposit(address _from, uint256 _value);
    event Withdraw(address _to, uint256 _value);

    // constructor
    function Betting() payable {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        owner = msg.sender;
        kickStarter.add(msg.value);
        oraclize_setCustomGasPrice(4000000000 wei);
    }

    // modifiers for restricting access to methods
    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier duringBetting {
        require(betting_open);
        _;
    }
    
    modifier beforeBetting {
        require(!betting_open);
        _;
    }

    modifier afterRace {
        require(race_end);
        _;
    }

    //oraclize callback method
    function __callback(bytes32 myid, string result, bytes proof) {
        require (msg.sender == oraclize_cbAddress());
        race_start = true;
        betting_open = false;
        coin_pointer = oraclizeIndex[myid];

        if (coinIndex[coin_pointer].price_check != true) {
            coinIndex[coin_pointer].pre = stringToUintNormalize(result);
            coinIndex[coin_pointer].price_check = true;
            newPriceTicker(coinIndex[coin_pointer].pre);
        } else if (coinIndex[coin_pointer].price_check == true){
            coinIndex[coin_pointer].post = stringToUintNormalize(result);
            newPriceTicker(coinIndex[coin_pointer].post);
            countdown = countdown - 1;
            if (countdown == 0) {
                reward();
            }
        }
    }

    // place a bet on a coin(horse) lockBetting
    function placeBet(bytes32 horse) external duringBetting payable  {
        require(msg.value >= 0.1 ether && msg.value <= 1.0 ether);
        bet_info memory current_bet;
        current_bet.amount = msg.value;
        current_bet.horse = horse;
        voterIndex[msg.sender].bets.push(current_bet);
        voterIndex[msg.sender].bet_count.add(1);
        coinIndex[horse].total = (coinIndex[horse].total).add(msg.value);
        coinIndex[horse].count = coinIndex[horse].count.add(1);
        Deposit(msg.sender, msg.value);
    }

    // fallback method for accepting payments
    function () payable {
        Deposit(msg.sender, msg.value);
    }

    // method to place the oraclize queries
    function update(uint delay, uint  locking_duration) onlyOwner beforeBetting payable {
        if (oraclize_getPrice("URL") > (this.balance)/6) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            starting_time = block.timestamp;
            betting_open = true;
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            // bets open price query
            delay = delay.add(60); //slack time 1 minute
            betting_duration = delay;
            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd");
            oraclizeIndex[temp_ID] = ETH;

            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd");
            oraclizeIndex[temp_ID] = BTC;

            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/litecoin/).0.price_usd");
            oraclizeIndex[temp_ID] = LTC;

            //bets closing price query
            delay.add(locking_duration);
            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd",300000);
            oraclizeIndex[temp_ID] = BTC;

            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd",300000);
            oraclizeIndex[temp_ID] = ETH;

            temp_ID = oraclize_query(delay, "URL", "json(http://api.coinmarketcap.com/v1/ticker/litecoin/).0.price_usd",300000);
            oraclizeIndex[temp_ID] = LTC;

            race_duration = delay;
        }
    }

    // method to calculate reward (called internally by callback)
    function reward() internal {
        /*
        calculating the difference in price with a precision of 5 digits
        not using safemath since signed integers are handled
        */
        BTC_delta = int(coinIndex[BTC].post - coinIndex[BTC].pre)*10000/int(coinIndex[BTC].pre);
        ETH_delta = int(coinIndex[ETH].post - coinIndex[ETH].pre)*10000/int(coinIndex[ETH].pre);
        LTC_delta = int(coinIndex[LTC].post - coinIndex[LTC].pre)*10000/int(coinIndex[LTC].pre);

        // throws when no bets are placed. since oraclize will eat some ethers from the kickStarter and kickStarter will be > balance
        total_reward = this.balance.sub(kickStarter); 

        // house fee 1%
        uint house_fee = total_reward.mul(1).div(100);
        total_reward = total_reward.sub(house_fee);
        require(this.balance > house_fee);
        owner.transfer(house_fee);

        if (BTC_delta > ETH_delta) {
            if (BTC_delta > LTC_delta) {
                winner_horse[BTC] = true;
                winnerPoolTotal = coinIndex[BTC].total;
            }
            else if(LTC_delta > BTC_delta) {
                winner_horse[LTC] = true;
                winnerPoolTotal = coinIndex[LTC].total;
            } else {
                winner_horse[BTC] = true;
                winner_horse[LTC] = true;
                winnerPoolTotal = coinIndex[BTC].total.add(coinIndex[LTC].total);
            }
        } else if(ETH_delta > BTC_delta) {
            if (ETH_delta > LTC_delta) {
                winner_horse[ETH] = true;
                winnerPoolTotal = coinIndex[ETH].total;
            }
            else if (LTC_delta > ETH_delta) {
                winner_horse[LTC] = true;
                winnerPoolTotal = coinIndex[LTC].total;
            } else {
                winner_horse[ETH] = true;
                winner_horse[LTC] = true;
                winnerPoolTotal = coinIndex[ETH].total.add(coinIndex[LTC].total);
            }
        } else {
            winner_horse[ETH] = true;
            winner_horse[BTC] = true;
            winnerPoolTotal = coinIndex[ETH].total.add(coinIndex[BTC].total);
        }
        race_end = true;
    }

    // method to calculate an invidual's reward
    function calculateReward(address candidate) internal afterRace constant returns(uint winner_reward) {
        uint i;
        voter_info bettor = voterIndex[candidate];
        if (!voided_bet) {
            for(i=0; i<bettor.bet_count; i++) {
                if (bettor.bets[i].horse == winner_horse) {
                    winner_reward += (((total_reward.mul(10000)).div(winnerPoolTotal)).mul(bettor.bets[i].amount)).div(10000);
                }
            }

        } else {
            for(i=0; i<bettor.bet_count; i++) {
                winner_reward += bettor.bets[i].amount;
            }
        }
    }

    // method to just check the reward amount
    function checkReward() afterRace constant returns (uint) {
        require(!voterIndex[msg.sender].rewarded);
        return calculateReward(msg.sender);
    }

    // method to claim the reward amount
    function claim_reward() afterRace {
        require(!voterIndex[msg.sender].rewarded);
        uint transfer_amount = calculateReward(msg.sender);
        require(this.balance > transfer_amount);
        voterIndex[msg.sender].rewarded = true;
        msg.sender.transfer(transfer_amount);
        Withdraw(msg.sender, transfer_amount);
    }

    // utility function to convert string to integer with precision consideration
    function stringToUintNormalize(string s) constant returns (uint result) {
        uint p =2;
        bool precision=false;
        bytes memory b = bytes(s);
        uint i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            if (precision == true) {p = p-1;}
            if (uint(b[i]) == 46){precision = true;}
            uint c = uint(b[i]);
            if (c >= 48 && c <= 57) {result = result * 10 + (c - 48);}
            if (precision==true && p == 0){return result;}
        }
        while (p!=0) {
            result = result*10;
            p=p-1;
        }
    }


    // exposing the coin pool details for DApp
    function getCoinIndex(bytes32 index) constant returns (uint, uint, uint, bool, uint) {
        return (coinIndex[index].total, coinIndex[index].pre, coinIndex[index].post, coinIndex[index].price_check, coinIndex[index].count);
    }

    // exposing the total reward amount for DApp
    function reward_total() constant returns (uint) {
        return (coinIndex[BTC].total.add(coinIndex[ETH].total).add(coinIndex[LTC].total));
    }

    // in case of any errors in race, enable full refund for the Bettors to claim
    //TODO: try and include more scenarios where the refund should be possible
    function kill_refund() onlyOwner {
        require(race_start);
        require(!race_end);
        require(now > starting_time+race_duration);
        voided_bet = true;
        race_end = true;
    }

    // method to claim unclaimed winnings after 30 day notice period
    function recovery() onlyOwner{
        require(now > starting_time+30 days);
        require(voided_bet ||  race_end);
        selfdestruct(owner);
    }

    function suicide() onlyOwner {
        selfdestruct(owner);
    }

    function getVoterIndex() constant returns (uint, bytes32, uint) {
        voter_info shit = voterIndex[msg.sender];
        return (shit.bet_count, shit.bets[0].horse, shit.bets[0].amount);
    }
}