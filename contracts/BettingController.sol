pragma solidity ^0.4.19;

import {Betting as Race, usingOraclize} from "./Betting.sol";

contract BettingController is usingOraclize {
    address owner;
    bool paused;
    uint256 oraclizeGasLimit;
    Race race;
    
    enum raceStatusChoices { Betting, Cooldown, Racing, RaceEnd, Aborted }
    
    struct raceInfo {
        uint256 spawnTime;
        raceStatusChoices raceStatus;
    }
    
    struct recoveryIndexInfo {
        address raceContract;
        bool recoveryNeeded;
    }
    
    struct oraclizeIndexInfo {
        uint256 bettingDuration;
        uint256 raceDuration;
    }
    
    mapping (address => raceInfo) raceIndex;
    mapping (bytes32 => recoveryIndexInfo) recoveryIndex;
    mapping (bytes32 => oraclizeIndexInfo) oracleIndex;
    event RaceDeployed(address _address, address _owner, uint256 _bettingDuration, uint256 _raceDuration, uint256 _time);
    event HouseFeeDeposit(address _race, uint256 _value);
    event newOraclizeQuery(string description);
    event AddFund(uint256 _value);

    modifier onlyOwmner {
        require(msg.sender == owner);
        _;
    }
    
    modifier whenNotPaused {
        require(!paused);
        _;
    }
    
    function BettingController() public payable {
        owner = msg.sender;
        oraclizeGasLimit = 4000000;
    }
    
    function addFunds() external onlyOwmner payable {
        AddFund(msg.value);
    }
    
    function () external payable{
        require(raceIndex[msg.sender].raceStatus == raceStatusChoices.RaceEnd);
        HouseFeeDeposit(msg.sender, msg.value);
    }

    function spawnRace(uint256 _bettingDuration, uint256 _raceDuration) payable whenNotPaused {
        require(!paused);
        bytes32 oracleRecoveryQueryId;
        race = (new Race).value(0.1 ether)();
        
        raceIndex[race].raceStatus = raceStatusChoices.Betting;
        raceIndex[race].spawnTime = now;
        assert(race.setupRace(_bettingDuration,_raceDuration));
        RaceDeployed(address(race), race.owner(), _bettingDuration, _raceDuration, now);
        oracleRecoveryQueryId=recoveryController(30 days);
        recoveryIndex[oracleRecoveryQueryId].raceContract = address(race);
        recoveryIndex[oracleRecoveryQueryId].recoveryNeeded = true;
    }
    
    function __callback(bytes32 oracleQueryId, string result, bytes proof) {
        require (msg.sender == oraclize_cbAddress());
        if (recoveryIndex[oracleQueryId].recoveryNeeded) {
            Race(address(recoveryIndex[oracleQueryId].raceContract)).recovery();
            recoveryIndex[oracleQueryId].recoveryNeeded = false;
        } else {
            spawnRace(oracleIndex[oracleQueryId].bettingDuration,oracleIndex[oracleQueryId].raceDuration);
            raceController(12 hours, oracleIndex[oracleQueryId].bettingDuration,oracleIndex[oracleQueryId].raceDuration); // spawn race every 12 hours
        }
    }
    
    function raceController(uint256 delay, uint256 _bettingDuration, uint256 _raceDuration) payable returns(bytes32){
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            bytes32 oracleQueryId; 
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oracleQueryId = oraclize_query(delay, "URL", "", oraclizeGasLimit);
            oracleIndex[oracleQueryId].bettingDuration = _bettingDuration;
            oracleIndex[oracleQueryId].raceDuration = _raceDuration;
            return oracleQueryId;
        }
    }
    
    function recoveryController(uint256 delay) payable returns(bytes32){
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            bytes32 oracleRecoveryQueryId; 
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oracleRecoveryQueryId = oraclize_query(delay, "URL", "", oraclizeGasLimit);
            return oracleRecoveryQueryId;
        }
    }
    
    function enableRefund(address _race) onlyOwmner {
        Race raceInstance = Race(_race);
        raceInstance.refund();
    }
    
    function raceSpawnSwitch(bool _status) external onlyOwmner {
        paused=_status;
    }
    /*
    @dev this method is used only for development purpose and won't be there in production
    */
    function kill() onlyOwmner {
        selfdestruct(owner);
    }
}
