pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import './interfaces/IPlearnFactory.sol';
import './PlearnPair.sol';

contract PlearnFactory is Initializable, IPlearnFactory {
    address public override feeTo;
    address public override feeToSetter;
    bytes32 public constant override INIT_CODE_HASH = keccak256(abi.encodePacked(type(PlearnPair).creationCode));

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    function initialize(address _feeToSetter) public initializer {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'Plearn: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Plearn: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Plearn: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(PlearnPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IPlearnPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, 'Plearn: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, 'Plearn: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setDevFee(address _pair, uint8 _devFee) external override {
        require(msg.sender == feeToSetter, 'Plearn: FORBIDDEN');
        require(_devFee > 0, 'Plearn: FORBIDDEN_FEE');
        PlearnPair(_pair).setDevFee(_devFee);
    }
    
    function setSwapFee(address _pair, uint32 _swapFee) external override {
        require(msg.sender == feeToSetter, 'Plearn: FORBIDDEN');
        PlearnPair(_pair).setSwapFee(_swapFee);
    }
}