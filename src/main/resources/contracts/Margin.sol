pragma solidity ^0.5.7;

#define TRANSPILE

#include "./common.sol"

#define COMPOUND_CONTROLLER_ADDR 0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b
#define C_ETHER_ADDR 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5

contract MarginSwap {
  uint256 _owner;
  uint256 _parent_address;

  uint256[2**160] _compound_lookup;

  constructor(address owner, address parent_address) public {
    assembly {
      sstore(_owner_slot, owner)
      sstore(_parent_address_slot, parent_address)
    }
  }

  function enterMarkets(address[] calldata cTokens) external {
    assembly {
      /* assert: array position is standard */
      if xor(0x20, calldataload(4)) {
        REVERT(1)
      }

      let array_length := calldataload(0x24)
      let array_start := 0x42

      /* assert: calldatasize fits data */
      if xor(add(0x24, array_length), calldatasize) {
        REVERT(2)
      }

      /* Step 1: enter all markets */
      {
        let call_input := mload(0x40)
        let call_input_size := calldatasize

        /* function signature is the same, so relay calldata */
        calldatacopy(
          /* free memory pointer */ call_input,
          /* start */ 0,
          /* size */ call_input_size
        )

        /* NOTE: using input memory to store output, safe? */
        let res := call(
          gas, COMPOUND_CONTROLLER_ADDR, 0,
          call_input,
          call_input_size,
          call_input,
          sub(call_input_size, 4)
        )

        if iszero(res) {
          REVERT(1)
        }

        /* assert: output array is standard */
        if xor(0x20, mload(call_input)) {
          REVERT(3)
        }

        /* assert: output array length matches input */
        if xor(array_length, mload(add(call_input, 0x20))) {
          REVERT(4)
        }

        let has_error := 0
        for { let i := 0 } lt(i, array_length) { i := add(i, 1) } {
          has_error := or(has_error, mload(add(add(call_input, 0x40), mul(i, 0x20))))
        }

        if has_error {
          REVERT(5)
        }
      }

      /* -------------------------------- */
      /*   Entered the compound markets   */
      /* -------------------------------- */

      /* Step 2+3 */
      let array_end := add(array_start, mul(array_length, 0x20))
      for { let i := array_start } lt(i, array_end) { i := add(i, 0x20) } {
        let cToken_addr := calldataload(i)

        let mem_ptr := mload(0x40)

        /* Step 2: register to lookup */
        {
          /* default to ETH address (0) */
          mstore(mem_ptr, 0)

          if xor(cToken_addr, C_ETHER_ADDR) {
            mstore(mem_ptr, fn_hash("underlying()"))

            let res := staticcall(
              gas, cToken_addr,
              mem_ptr, 4,
              mem_ptr, 32
            )

            if iszero(res) {
              REVERT(6)
            }
          }
        }

        let underlying_addr := mload(mem_ptr)
        sstore(add(_compound_lookup_slot, underlying_addr), cToken_addr)

        /* Step 3: approve transfers from here to cToken */
        {
          mstore(mem_ptr, fn_hash("approve(address)"))
          mstore(add(mem_ptr, 4), cToken_addr)

          let mem_out := add(mem_ptr, 0x24)

          let res := staticcall(
            gas, underlying_addr,
            mem_ptr, 0x24,
            mem_out, 0x20
          )

          if or(iszero(res), iszero(mload(mem_out))) {
            REVERT(7)
          }
        }
      }
    }
  }

  #define APPROVE(TOKEN, CONTRACT, AMOUNT, REVERT_1) \
    { \
      mstore(m_in, fn_hash("approve(uint256)")) \
      mstore(add(m_in, 4), AMOUNT) \
      mstore(m_out, 0) \
      let res := call( \
        gas, CONTRACT, 0, \
        m_in, 36, \
        m_out, 32 \
      ) \
      if or(iszero(res), iszero(mload(m_out))) { \
        REVERT(REVERT_1) \
      } \
    }

  function depositEth() external payable {
    deposit(address(0x0), msg.value);
  }

  function deposit(address asset_address, uint256 amount) public payable {
    uint256[4] memory m_in;
    uint256[1] memory m_out;

    assembly {
      /* if ETH, ensure call value matches amount */
      if and(iszero(asset_address), xor(amount, callvalue)) {
        REVERT(1)
      }

      /* transfer amount to this contract */
      if asset_address {
        if callvalue {
          REVERT(2)
        }

        mstore(m_in, fn_hash("transferFrom(address,address,uint256)"))
        mstore(add(m_in, 4), caller)
        mstore(add(m_in, 0x24), address)
        mstore(add(m_in, 0x44), amount)

        mstore(m_out, 0)
        let res := call(
          gas, asset_address, 0,
          m_in, 0x64,
          m_out, 0x20
        )

        if or(iszero(res), iszero(mload(m_out))) {
          REVERT(3)
        }
      }
    }

    depositToCompound(asset_address, amount);
  }

  /* assumes amount exists in contract's wallet */
  function depositToCompound(address asset_address, uint256 amount) internal {
    uint256[2] memory m_in;
    uint256[1] memory m_out;

    assembly {
      let c_address := sload(add(_compound_lookup_slot, asset_address))
      if iszero(c_address) {
        REVERT(100)
      }

      /* Step 1. Get borrow amount */
      {
        mstore(m_in, fn_hash("borrowBalanceCurrent(address)"))
        mstore(add(m_in, 4), caller)
        
        let res := staticcall(
          gas, c_address,
          m_in, 36,
          m_out, 32
        )
        
        if iszero(res) {
          REVERT(101)
        }
      }

      /* Step 2. Repay max possible borrow */
      {
        let borrow_amount := mload(m_out)

        let to_repay := borrow_amount
        if lt(amount, to_repay) {
          to_repay := amount
        }

        if to_repay {
          mstore(m_in, fn_hash("repayBorrow()"))
          let m_in_size := 4
          let wei_to_send := to_repay

          if xor(c_address, C_ETHER_ADDR) {
            mstore(m_in, fn_hash("repayBorrow(uint256)"))
            mstore(add(m_in, 4), to_repay)
            m_in_size := 36
            wei_to_send := 0
          }

          let result := call(
            gas, c_address, wei_to_send,
            m_in, m_in_size,
            m_out, 32
          )

          if iszero(result) {
            REVERT(102)
          }

          switch returndatasize()
          /* called cEther */
          case 0 {
            if xor(c_address, C_ETHER_ADDR) {
              REVERT(103)
            }
          }
          /* called CErc20 */
          case 32 {
            if mload(m_out) {
              REVERT(104)
            }
          }
          /* called Unknown */
          default {
            REVERT(105)
          }

          amount := sub(amount, to_repay)
        }
      }

      /* Step 3. Mint remaining amount */
      {
        if amount {
          mstore(m_in, fn_hash("mint()"))
          let m_in_size := 4
          let wei_to_send := amount

          if xor(c_address, C_ETHER_ADDR) {
            mstore(m_in, fn_hash("mint(uint256)"))
            mstore(add(m_in, 4), amount)
            m_in_size := 36
            wei_to_send := 0
          }

          let result := call(
            gas, c_address, wei_to_send,
            m_in, m_in_size,
            m_out, 32
          )

          switch returndatasize()
          /* called cEther */
          case 0 {
            if xor(c_address, C_ETHER_ADDR) {
              REVERT(106)
            }
          }
          /* called CErc20 */
          case 32 {
            if mload(m_out) {
              REVERT(107)
            }
          }
          /* called Unknown */
          default {
            REVERT(108)
          }
        }
      }
    }
  }

  function withdraw(address asset, uint256 amount, address destination) public {
    uint256[2] memory m_in;
    uint256[1] memory m_out;

    assembly {
      let c_address := sload(add(_compound_lookup_slot, asset))
      if iszero(c_address) {
        REVERT(200)
      }

      /* Step 1. Get avaiable balance */
      {
        mstore(m_in, fn_hash("balanceOfUnderlying(address)"))
        mstore(add(m_in, 4), caller)
        
        let res := staticcall(
          gas, c_address,
          m_in, 36,
          m_out, 32
        )
        
        if iszero(res) {
          REVERT(201)
        }
      }

      /* Step 2. Reedeem */
      {
        let available := mload(m_out)

        let to_redeem := available
        if lt(amount, to_redeem) {
          to_redeem := amount
        }

        if to_redeem {
          mstore(m_in, fn_hash("redeemUnderlying(uint256)"))
          mstore(add(m_in, 4), to_redeem)

          let result := call(
            gas, c_address, 0,
            m_in, 36,
            m_out, 32
          )

          if iszero(result) {
            REVERT(202)
          }

          if mload(m_out) {
            REVERT(203)
          }

          amount := sub(amount, to_redeem)
        }
      }

      /* Step 3. Borrow Remaining */
      {
        if amount {
          mstore(m_in, fn_hash("borrow(uint256)"))
          mstore(add(m_in, 4), amount)

          let result := call(
            gas, c_address, 0,
            m_in, 36,
            m_out, 32
          )

          if mload(m_out) {
            REVERT(204)
          }
        }
      }

      /* Step 4. Send acquired funds */
      {
        if amount {
          mstore(m_in, fn_hash("borrow(uint256)"))
          mstore(add(m_in, 4), amount)

          let result := call(
            gas, c_address, 0,
            m_in, 36,
            m_out, 32
          )

          if mload(m_out) {
            REVERT(204)
          }
        }
      }
    }
  }

  function transferOut(address asset, uint256 amount, address destination) external {
    assembly {
      if xor(caller, sload(_owner_slot)) {
        REVERT(1)
      }
    }
  }

  #define BALANCE_OF(TOKEN, OWNER, REVERT_1) \
    { \
      mstore(m_in, fn_hash("balanceOf(address)")) \
      mstore(add(m_in, 4), OWNER) \
      mstore(m_out, 0) \
      let res := staticcall( \
        gas, TOKEN, \
        m_in, 0x24, \
        m_out, 32 \
      ) \
      if iszero(res) { \
        REVERT(REVERT_1) \
      } \
    }

  function trade(address input_asset,
                 uint256 input_amount,
                 address output_asset,
                 uint256 min_output_amount,
                 address trade_contract,
                 bytes memory trade_data) public payable {

    uint256[4] memory m_in;
    uint256[1] memory m_out;
    uint256 output_amount;

    assembly {
      if xor(caller, sload(_owner_slot)) {
        REVERT(1)
      }

      let capital_source := sload(_parent_address_slot)

      /* Step 1: Get source capital from parent contract */
      {
        mstore(m_in, fn_hash("getCapital(address,address,uint256)"))
        mstore(add(m_in, 0x04), sload(_owner_slot))
        mstore(add(m_in, 0x24), input_asset)
        mstore(add(m_in, 0x44), input_amount)

        let res := call(
          gas, capital_source, 0,
          m_in, 100,
          0, 0
        )

        if iszero(res) {
          REVERT(2)
        }
      }

      /* Step 2: Allow trade contract to use capital for trade */
      if input_asset {
        /* only accept payment if using ETH as from */
        if callvalue {
          REVERT(3)
        }

        APPROVE(input_asset, trade_contract, input_amount, /* REVERT(4) */ 4)
      }

      BALANCE_OF(caller, output_asset, /* REVERT(5) */ 5)
      let before_balance := mload(m_out)

      /* Step 3: Execute trade */
      {
        /* TODO: what happens if signature returns memory? */
        /* TODO: test with Uniswap, Kyber, 0x */
        let res := call(
          gas, trade_contract, callvalue,
          add(trade_data, 0x20), mload(trade_data),
          0, 0
        )

        if iszero(res) {
          REVERT(6)
        }
      }

      APPROVE(input_asset, trade_contract, 0, /* REVERT(7) */ 7)

      BALANCE_OF(caller, output_asset, /* REVERT(8) */ 8)
      let after_balance := mload(m_out)

      if lt(before_balance, after_balance) {
        REVERT(9)
      }

      output_amount := sub(after_balance, before_balance)
      if lt(output_amount, min_output_amount) {
        REVERT(10)
      }
    }

    /* Step 4: Deposit trade output into money market */
    depositToCompound(output_asset, output_amount);

    /* Step 5: Borrow funds to repay parent */
    withdraw(input_asset, input_amount, address(_parent_address));
  }
}

