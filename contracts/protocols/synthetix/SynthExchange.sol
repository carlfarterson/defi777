pragma solidity >=0.6.2 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../tokens/Wrapped777.sol";
import "../uniswap/IUniswapV2Router01.sol";
import "./interfaces/ISynthetix.sol";
import "../../Receiver.sol";

contract SynthExchange is Receiver {
  Wrapped777 public outputWrapper;
  IUniswapV2Router01 public router;
  ISynthetix public snx;
  bytes32 public outputKey;

  bytes32 constant private SUSD = 0x7355534400000000000000000000000000000000000000000000000000000000;

  bool private wrapping = false;

  constructor(Wrapped777 _output, address _snx, address _router) public {
    outputWrapper = _output;
    snx = ISynthetix(_snx);
    router = IUniswapV2Router01(_router);
    outputKey = snx.synthsByAddress(address(_output.token()));
  }

  receive() external payable {
    address[] memory path = new address[](2);
    path[0] = router.WETH();
    path[1] = address(snx.synths(SUSD));

    router.swapExactETHForTokens{value: msg.value}(0, path, address(this), now);

    uint256 outputAmount = synthExchange(SUSD);

    wrapAndReturn(msg.sender, outputAmount);
  }

  function _tokensReceived(IERC777 _token, address from, uint256 amount, bytes memory /*data*/) internal override {
    if (address(_token) == address(outputWrapper) && wrapping) {
      return;
    }

    Wrapped777 _wrapper = Wrapped777(address(_token));
    _token.send(address(_token), amount, "");

    ERC20 unwrappedToken = _wrapper.token();

    bytes32 inputKey = snx.synthsByAddress(address(unwrappedToken));
    if (inputKey == bytes32(0)) {
      swapToSUSD(unwrappedToken);
      inputKey = SUSD;
    }

    uint256 outputAmount = synthExchange(inputKey);

    wrapAndReturn(from, outputAmount);
  }

  function synthExchange(bytes32 inputKey) private returns (uint256) {
    ERC20 inputToken = ERC20(address(snx.synths(inputKey)));
    uint256 amount = inputToken.balanceOf(address(this));
    return snx.exchange(inputKey, amount, outputKey);
  }

  function swapToSUSD(ERC20 token) private {
    uint unwrappedBalance = token.balanceOf(address(this));
    token.approve(address(router), unwrappedBalance);

    address[] memory path = new address[](3);
    path[0] = address(token);
    path[1] = router.WETH();
    path[2] = address(snx.synths(SUSD));

    router.swapExactTokensForTokens(unwrappedBalance, 0 /*amountOutMin*/, path, address(this), now);
  }

  function wrapAndReturn(address recipient, uint256 amount) private {
    wrapping = true;
    outputWrapper.token().approve(address(outputWrapper), amount);
    uint256 wrappedAmount = outputWrapper.wrap(amount);
    outputWrapper.transfer(recipient, wrappedAmount);
    wrapping = false;
  }
}
