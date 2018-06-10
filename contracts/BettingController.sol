pragma solidity ^0.4.20;

import {Betting as Race, usingOraclize} from "./Betting.sol";

contract BettingController is usingOraclize {
    address owner;
    address house_takeout = 0xf783A81F046448c38f3c863885D9e99D10209779;
    bool public paused;
    uint256 oraclizeGasLimit;
    uint256 raceKickstarter;
    uint256 recoveryDuration;
    Race race;
    
    struct raceInfo {
        uint256 spawnTime;
        uint256 bettingDuration;
        uint256 raceDuration;
    }
    
    struct recoveryIndexInfo {
        address raceContract;
        bool recoveryNeeded;
    }
    
    struct oraclizeIndexInfo {
        bool deployed;
        uint256 delay;
        uint256 bettingDuration;
        uint256 raceDuration;
    }
    
    mapping (address => raceInfo) public raceIndex;
    mapping (bytes32 => recoveryIndexInfo) recoveryIndex;
    mapping (bytes32 => oraclizeIndexInfo) oracleIndex;
    event RaceDeployed(address _address, address _owner, uint256 _bettingDuration, uint256 _raceDuration, uint256 _time);
    event HouseFeeDeposit(address indexed _race, uint256 _value);
    event newOraclizeQuery(string description);
    event AddFund(uint256 _value);
    event RemoteBettingCloseInfo(address _race);

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    modifier whenNotPaused {
        require(!paused);
        _;
    }
    
    function BettingController() public payable {
        owner = msg.sender;
        oraclizeGasLimit = 3500000;
        oraclize_setCustomGasPrice(15000000000 wei);
        raceKickstarter = 0.03 ether;
        recoveryDuration = 32 days;
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
    }
    
    function addFunds() external onlyOwner payable {
        emit AddFund(msg.value);
    }
    
    function remoteBettingClose() external {
        emit RemoteBettingCloseInfo(msg.sender);
    }
    
    function depositHouseTakeout() external payable{
        house_takeout.transfer(msg.value);
        emit HouseFeeDeposit(msg.sender, msg.value);
    }

    function spawnRace(uint256 _bettingDuration, uint256 _raceDuration) internal whenNotPaused {
        require(!paused);
        bytes32 oracleRecoveryQueryId;
        race = (new Race).value(raceKickstarter)();

        raceIndex[race].spawnTime = now;
        raceIndex[race].bettingDuration = _bettingDuration;
        raceIndex[race].raceDuration = _raceDuration;
        assert(race.setupRace(_bettingDuration,_raceDuration));
        emit RaceDeployed(address(race), race.owner(), _bettingDuration, _raceDuration, now);
        // oracleRecoveryQueryId=recoveryController(recoveryDuration);
        // recoveryIndex[oracleRecoveryQueryId].raceContract = address(race);
        recoveryIndex[oracleRecoveryQueryId].recoveryNeeded = true;
    }
    
    // function __callback(bytes32 oracleQueryId, string result, bytes proof) public {
    //     require (msg.sender == oraclize_cbAddress());
    //     if (recoveryIndex[oracleQueryId].recoveryNeeded) {
    //         Race(address(recoveryIndex[oracleQueryId].raceContract)).recovery();
    //         recoveryIndex[oracleQueryId].recoveryNeeded = false;
    //     } else {
    //         require(!oracleIndex[oracleQueryId].deployed);
    //         oracleIndex[oracleQueryId].deployed = true;
    //         spawnRace(oracleIndex[oracleQueryId].bettingDuration,oracleIndex[oracleQueryId].raceDuration);
    //         raceController(oracleIndex[oracleQueryId].delay, oracleIndex[oracleQueryId].bettingDuration,oracleIndex[oracleQueryId].raceDuration); 
    //     }
    // }
    
    function raceController(uint256 _delay, uint256 _bettingDuration, uint256 _raceDuration) internal returns(bytes32){
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            bytes32 oracleQueryId;
            oracleQueryId = oraclize_query(_delay, "URL", "", oraclizeGasLimit);
            oracleIndex[oracleQueryId].bettingDuration = _bettingDuration;
            oracleIndex[oracleQueryId].raceDuration = _raceDuration;
            oracleIndex[oracleQueryId].delay = _delay;
            emit newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            return oracleQueryId;
        }
    }
    
    function recoveryController(uint256 delay) internal returns(bytes32){
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            bytes32 oracleRecoveryQueryId; 
            oracleRecoveryQueryId = oraclize_query(delay, "URL", "", oraclizeGasLimit);
            emit newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            return oracleRecoveryQueryId;
        }
    }
    
    function initiateRaceSpawning(uint256 _delay, uint256 _bettingDuration, uint256 _raceDuration) external onlyOwner {
        uint delay = _delay - 15 minutes; //decreasing delay to prevent delay in race deployment.
        spawnRace(_bettingDuration,_raceDuration);
        raceController(delay, _bettingDuration, _raceDuration);
    }
    
    function spawnRaceManual(uint256 _bettingDuration, uint256 _raceDuration) external onlyOwner {
        spawnRace(_bettingDuration,_raceDuration);
    }
    
    function enableRefund(address _race) external onlyOwner {
        Race raceInstance = Race(_race);
        raceInstance.refund();
    }
    
    function manualRecovery(address _race) external onlyOwner {
        Race raceInstance = Race(_race);
        raceInstance.recovery();
    }
    
    function changeRaceOwnership(address _race, address _newOwner) external onlyOwner {
        Race raceInstance = Race(_race);
        raceInstance.changeOwnership(_newOwner);
    }
    
    function changeHouseTakeout(address _newHouseTakeout) external onlyOwner {
        require(house_takeout != _newHouseTakeout);
        house_takeout = _newHouseTakeout;
    }
    
    function changeOraclizeGasPrice(uint256 _newGasPrice) external onlyOwner {
        uint256 newGasPrice = _newGasPrice*1000000000 wei;
        oraclize_setCustomGasPrice(newGasPrice);
    }
    
    function raceSpawnSwitch(bool _status) external onlyOwner {
        paused=_status;
    }
    
    function extractFund(uint256 _amount) external onlyOwner {
        if (_amount == 0) {
            owner.transfer(address(this).balance);
        } else {
            require(_amount <= address(this).balance);
            owner.transfer(_amount);   
        }
    }
}