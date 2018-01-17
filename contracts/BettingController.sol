pragma solidity ^0.4.0;

import {Betting as Race, usingOraclize} from "./Betting.sol";
// import "./lib/usingOraclize.sol";
// import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";


contract BettingController is usingOraclize {
    address owner;
    uint256 raceCounter;
    
    enum raceStatusChoices { Waiting, Betting, Cooldown, Racing, RaceEnd }
    
    struct raceInfo {
        uint256 spawnTime;
        raceStatusChoices raceStatus;
    }
    
    mapping (address => raceInfo) raceIndex;
    event RaceDeployed(address _race, address _owner);
    event HouseFeeDeposit(address _race, uint256 _value);
    event newOraclizeQuery(string description);

    
    function BettingController() public payable {
        owner = msg.sender;
        // update(0);
    }
    
    function () external payable{
        require(raceIndex[msg.sender].raceStatus == raceStatusChoices.RaceEnd);
        HouseFeeDeposit(msg.sender, msg.value);
    }

    function spawnRace() internal {
        Race race = new Race();
        RaceDeployed(race, race.owner());
    }
    
    function __callback(bytes32 myid, string result, bytes proof) {
        require (msg.sender == oraclize_cbAddress());
        spawnRace();
        update(60,4000000);
    }
    
    function update(uint delay, uint oraclizeGasLimit) payable {
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query(delay, "URL", "", oraclizeGasLimit);
        }
    }
}
