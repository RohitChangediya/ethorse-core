pragma solidity ^0.4.0;

contract Race {
    address private owner;
    
    function Race() public{
        owner = msg.sender;
    }
    
    function getOwner() external view returns(address){return owner;}
}
