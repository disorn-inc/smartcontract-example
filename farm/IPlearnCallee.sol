pragma solidity >=0.8.0;

interface IPlearnCallee {
    function plearnCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}