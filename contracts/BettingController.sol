pragma solidity ^0.4.20;

import {Betting as Race} from "./Betting.sol";

contract BettingController {
    address owner;
    address house_takeout = 0xf783A81F046448c38f3c863885D9e99D10209779;
    uint256 raceKickstarter;
    Race race;
    
    struct raceInfo {
        uint256 spawnTime;
        uint256 bettingDuration;
        uint256 raceDuration;
    }

    mapping (address => raceInfo) public raceIndex;
    event RaceDeployed(address _address, address _owner, uint256 _bettingDuration, uint256 _raceDuration, uint256 _time);
    event HouseFeeDeposit(address indexed _race, uint256 _value);
    event AddFund(uint256 _value);
    event RemoteBettingCloseInfo(address _race);

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function BettingController() public payable {
        owner = msg.sender;
        raceKickstarter = 0.03 ether;
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

    function spawnRace(uint256 _bettingDuration, uint256 _raceDuration) internal {
        race = (new Race).value(raceKickstarter)();

        raceIndex[race].spawnTime = now;
        raceIndex[race].bettingDuration = _bettingDuration;
        raceIndex[race].raceDuration = _raceDuration;
        assert(race.setupRace(_bettingDuration,_raceDuration));
        emit RaceDeployed(address(race), race.owner(), _bettingDuration, _raceDuration, now);

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
    
    function extractFund(uint256 _amount) external onlyOwner {
        if (_amount == 0) {
            owner.transfer(address(this).balance);
        } else {
            require(_amount <= address(this).balance);
            owner.transfer(_amount);   
        }
    }
}