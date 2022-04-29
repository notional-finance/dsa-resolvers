// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import { NotionalInterface, Token, AssetRateParameters } from "./interfaces.sol";
import { DSMath } from "../../../utils/dsmath.sol";

contract Helpers is DSMath {
    /// @dev Contract address is different on Kovan: 0x0EAE7BAdEF8f95De91fDDb74a89A786cF891Eb0e
    NotionalInterface internal constant notional = NotionalInterface(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    /*
     * Minimum value signed 64.64-bit fixed point number may have.
     */
    int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;

    /*
     * Maximum value signed 64.64-bit fixed point number may have.
     */
    int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint256 private constant SECONDS_IN_YEAR = 31104000;

    // Number of decimal places that rates are stored in, equals 100%
    int256 internal constant RATE_PRECISION = 1e9;

    // Asset rates are in 1e18 decimals (cToken exchange rates), internal balances
    // are in 1e8 decimals. Therefore we leave this as 1e18 / 1e8 = 1e10
    int256 private constant ASSET_RATE_DECIMAL_DIFFERENCE = 1e10;

    uint8 internal constant LEND_TRADE = 0;
    uint8 internal constant BORROW_TRADE = 1;

    /// @notice Converts an internal underlying cash value to its asset cash value
    /// @param ar exchange rate object between asset and underlying
    /// @param underlyingBalance amount to convert to asset cash, denominated in internal token precision
    function convertFromUnderlying(AssetRateParameters memory ar, int256 underlyingBalance)
        internal
        pure
        returns (int256 assetBalance)
    {
        // Calculation here represents:
        // rateDecimals * balance * underlyingPrecision / rate * internalPrecision
        assetBalance = (underlyingBalance * ASSET_RATE_DECIMAL_DIFFERENCE * ar.underlyingDecimals) / ar.rate;
    }

    function getNetCashToAccount(uint16 currencyId, int256 cashUnderlying)
        internal
        view
        returns (int256 netCashToAccount)
    {
        // prettier-ignore
        (
            /* Token memory assetToken */,
            /* Token memory underlyingToken */,
            /* ETHRate memory ethRate */,
            AssetRateParameters memory assetRate
        ) = notional.getCurrencyAndRates(currencyId);

        netCashToAccount = convertFromUnderlying(assetRate, cashUnderlying);
    }

    function calculatefCashAndExchangeRate(
        uint16 currencyId,
        int256 netCashToAccount,
        uint8 marketIndex,
        uint256 blockTime,
        uint256 maturity,
        int128 defaultAnnualizedSlippage
    )
        internal
        view
        returns (
            int256 fCashAmount,
            int256 exchangeRatePostSlippage,
            int256 annualizedRate
        )
    {
        require(
            netCashToAccount >= type(int88).min && netCashToAccount <= type(int88).max,
            "netCashToAccount overflow"
        );

        fCashAmount = notional.getfCashAmountGivenCashAmount(
            currencyId,
            int88(netCashToAccount),
            uint256(marketIndex),
            blockTime
        );

        // exchangeRate = abs(fCashAmount * RATE_PRECISION / netCashToAccount)
        int256 exchangeRate = (fCashAmount * RATE_PRECISION) / netCashToAccount;
        if (exchangeRate < 0) exchangeRate *= -1;

        int256 exchangeSlippageFactor = interestToExchangeRate(defaultAnnualizedSlippage, blockTime, maturity);

        // Exchange rates are non-linear so we apply slippage using the exponent identity:
        // exchangeRatePostSlippage = e^((r + delta) * t)
        // exchangeRate = e^(r * t)
        // slippageFactor = e^(delta * t)
        // exchangeRatePostSlippage = exchangeRate * slippageFactor
        exchangeRatePostSlippage = (exchangeRate * exchangeSlippageFactor) / RATE_PRECISION;

        annualizedRate = exchangeToInterestRate(exchangeRatePostSlippage, blockTime, maturity);
    }

    /**
     * @notice Calculate binary exponent of x.  Revert on overflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function exp_2(int128 x) internal pure returns (int128) {
        require(x < 0x400000000000000000); // Overflow

        if (x < -0x400000000000000000) return 0; // Underflow

        uint256 result = 0x80000000000000000000000000000000;

        if (x & 0x8000000000000000 > 0) result = (result * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
        if (x & 0x4000000000000000 > 0) result = (result * 0x1306FE0A31B7152DE8D5A46305C85EDEC) >> 128;
        if (x & 0x2000000000000000 > 0) result = (result * 0x1172B83C7D517ADCDF7C8C50EB14A791F) >> 128;
        if (x & 0x1000000000000000 > 0) result = (result * 0x10B5586CF9890F6298B92B71842A98363) >> 128;
        if (x & 0x800000000000000 > 0) result = (result * 0x1059B0D31585743AE7C548EB68CA417FD) >> 128;
        if (x & 0x400000000000000 > 0) result = (result * 0x102C9A3E778060EE6F7CACA4F7A29BDE8) >> 128;
        if (x & 0x200000000000000 > 0) result = (result * 0x10163DA9FB33356D84A66AE336DCDFA3F) >> 128;
        if (x & 0x100000000000000 > 0) result = (result * 0x100B1AFA5ABCBED6129AB13EC11DC9543) >> 128;
        if (x & 0x80000000000000 > 0) result = (result * 0x10058C86DA1C09EA1FF19D294CF2F679B) >> 128;
        if (x & 0x40000000000000 > 0) result = (result * 0x1002C605E2E8CEC506D21BFC89A23A00F) >> 128;
        if (x & 0x20000000000000 > 0) result = (result * 0x100162F3904051FA128BCA9C55C31E5DF) >> 128;
        if (x & 0x10000000000000 > 0) result = (result * 0x1000B175EFFDC76BA38E31671CA939725) >> 128;
        if (x & 0x8000000000000 > 0) result = (result * 0x100058BA01FB9F96D6CACD4B180917C3D) >> 128;
        if (x & 0x4000000000000 > 0) result = (result * 0x10002C5CC37DA9491D0985C348C68E7B3) >> 128;
        if (x & 0x2000000000000 > 0) result = (result * 0x1000162E525EE054754457D5995292026) >> 128;
        if (x & 0x1000000000000 > 0) result = (result * 0x10000B17255775C040618BF4A4ADE83FC) >> 128;
        if (x & 0x800000000000 > 0) result = (result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB) >> 128;
        if (x & 0x400000000000 > 0) result = (result * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9) >> 128;
        if (x & 0x200000000000 > 0) result = (result * 0x10000162E43F4F831060E02D839A9D16D) >> 128;
        if (x & 0x100000000000 > 0) result = (result * 0x100000B1721BCFC99D9F890EA06911763) >> 128;
        if (x & 0x80000000000 > 0) result = (result * 0x10000058B90CF1E6D97F9CA14DBCC1628) >> 128;
        if (x & 0x40000000000 > 0) result = (result * 0x1000002C5C863B73F016468F6BAC5CA2B) >> 128;
        if (x & 0x20000000000 > 0) result = (result * 0x100000162E430E5A18F6119E3C02282A5) >> 128;
        if (x & 0x10000000000 > 0) result = (result * 0x1000000B1721835514B86E6D96EFD1BFE) >> 128;
        if (x & 0x8000000000 > 0) result = (result * 0x100000058B90C0B48C6BE5DF846C5B2EF) >> 128;
        if (x & 0x4000000000 > 0) result = (result * 0x10000002C5C8601CC6B9E94213C72737A) >> 128;
        if (x & 0x2000000000 > 0) result = (result * 0x1000000162E42FFF037DF38AA2B219F06) >> 128;
        if (x & 0x1000000000 > 0) result = (result * 0x10000000B17217FBA9C739AA5819F44F9) >> 128;
        if (x & 0x800000000 > 0) result = (result * 0x1000000058B90BFCDEE5ACD3C1CEDC823) >> 128;
        if (x & 0x400000000 > 0) result = (result * 0x100000002C5C85FE31F35A6A30DA1BE50) >> 128;
        if (x & 0x200000000 > 0) result = (result * 0x10000000162E42FF0999CE3541B9FFFCF) >> 128;
        if (x & 0x100000000 > 0) result = (result * 0x100000000B17217F80F4EF5AADDA45554) >> 128;
        if (x & 0x80000000 > 0) result = (result * 0x10000000058B90BFBF8479BD5A81B51AD) >> 128;
        if (x & 0x40000000 > 0) result = (result * 0x1000000002C5C85FDF84BD62AE30A74CC) >> 128;
        if (x & 0x20000000 > 0) result = (result * 0x100000000162E42FEFB2FED257559BDAA) >> 128;
        if (x & 0x10000000 > 0) result = (result * 0x1000000000B17217F7D5A7716BBA4A9AE) >> 128;
        if (x & 0x8000000 > 0) result = (result * 0x100000000058B90BFBE9DDBAC5E109CCE) >> 128;
        if (x & 0x4000000 > 0) result = (result * 0x10000000002C5C85FDF4B15DE6F17EB0D) >> 128;
        if (x & 0x2000000 > 0) result = (result * 0x1000000000162E42FEFA494F1478FDE05) >> 128;
        if (x & 0x1000000 > 0) result = (result * 0x10000000000B17217F7D20CF927C8E94C) >> 128;
        if (x & 0x800000 > 0) result = (result * 0x1000000000058B90BFBE8F71CB4E4B33D) >> 128;
        if (x & 0x400000 > 0) result = (result * 0x100000000002C5C85FDF477B662B26945) >> 128;
        if (x & 0x200000 > 0) result = (result * 0x10000000000162E42FEFA3AE53369388C) >> 128;
        if (x & 0x100000 > 0) result = (result * 0x100000000000B17217F7D1D351A389D40) >> 128;
        if (x & 0x80000 > 0) result = (result * 0x10000000000058B90BFBE8E8B2D3D4EDE) >> 128;
        if (x & 0x40000 > 0) result = (result * 0x1000000000002C5C85FDF4741BEA6E77E) >> 128;
        if (x & 0x20000 > 0) result = (result * 0x100000000000162E42FEFA39FE95583C2) >> 128;
        if (x & 0x10000 > 0) result = (result * 0x1000000000000B17217F7D1CFB72B45E1) >> 128;
        if (x & 0x8000 > 0) result = (result * 0x100000000000058B90BFBE8E7CC35C3F0) >> 128;
        if (x & 0x4000 > 0) result = (result * 0x10000000000002C5C85FDF473E242EA38) >> 128;
        if (x & 0x2000 > 0) result = (result * 0x1000000000000162E42FEFA39F02B772C) >> 128;
        if (x & 0x1000 > 0) result = (result * 0x10000000000000B17217F7D1CF7D83C1A) >> 128;
        if (x & 0x800 > 0) result = (result * 0x1000000000000058B90BFBE8E7BDCBE2E) >> 128;
        if (x & 0x400 > 0) result = (result * 0x100000000000002C5C85FDF473DEA871F) >> 128;
        if (x & 0x200 > 0) result = (result * 0x10000000000000162E42FEFA39EF44D91) >> 128;
        if (x & 0x100 > 0) result = (result * 0x100000000000000B17217F7D1CF79E949) >> 128;
        if (x & 0x80 > 0) result = (result * 0x10000000000000058B90BFBE8E7BCE544) >> 128;
        if (x & 0x40 > 0) result = (result * 0x1000000000000002C5C85FDF473DE6ECA) >> 128;
        if (x & 0x20 > 0) result = (result * 0x100000000000000162E42FEFA39EF366F) >> 128;
        if (x & 0x10 > 0) result = (result * 0x1000000000000000B17217F7D1CF79AFA) >> 128;
        if (x & 0x8 > 0) result = (result * 0x100000000000000058B90BFBE8E7BCD6D) >> 128;
        if (x & 0x4 > 0) result = (result * 0x10000000000000002C5C85FDF473DE6B2) >> 128;
        if (x & 0x2 > 0) result = (result * 0x1000000000000000162E42FEFA39EF358) >> 128;
        if (x & 0x1 > 0) result = (result * 0x10000000000000000B17217F7D1CF79AB) >> 128;

        result >>= uint256(uint128(63 - (x >> 64)));
        require(result <= uint256(int256(MAX_64x64)));

        return int128(uint128(result));
    }

    /**
     * @notice Calculate natural exponent of x.  Revert on overflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function exp(int128 x) internal pure returns (int128) {
        require(x < 0x400000000000000000); // Overflow

        if (x < -0x400000000000000000) return 0; // Underflow

        return exp_2(int128((int256(x) * 0x171547652B82FE1777D0FFDA0D23A7D12) >> 128));
    }

    /**
     * Calculate binary logarithm of x.  Revert if x <= 0.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function log_2(int128 x) internal pure returns (int128) {
        require(x > 0);

        int256 msb = 0;
        int256 xc = x;
        if (xc >= 0x10000000000000000) {
            xc >>= 64;
            msb += 64;
        }
        if (xc >= 0x100000000) {
            xc >>= 32;
            msb += 32;
        }
        if (xc >= 0x10000) {
            xc >>= 16;
            msb += 16;
        }
        if (xc >= 0x100) {
            xc >>= 8;
            msb += 8;
        }
        if (xc >= 0x10) {
            xc >>= 4;
            msb += 4;
        }
        if (xc >= 0x4) {
            xc >>= 2;
            msb += 2;
        }
        if (xc >= 0x2) msb += 1; // No need to shift xc anymore

        int256 result = (msb - 64) << 64;
        uint256 ux = uint256(int256(x)) << uint256(127 - msb);
        for (int256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
            ux *= ux;
            uint256 b = ux >> 255;
            ux >>= 127 + b;
            result += bit * int256(b);
        }

        return int128(result);
    }

    /**
     * Calculate natural logarithm of x.  Revert if x <= 0.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function ln(int128 x) internal pure returns (int128) {
        require(x > 0);

        int128 logVal = log_2(x);

        require(logVal > 0);

        return int128(uint128((uint256(uint128(logVal)) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF) >> 128));
    }

    /**
     * @notice Returns a new fCash amount after applying some amount of slippage
     *
     * @param annualizedSlippage positive or negative amount of slippage in annualized basis points
     * @param blockTime block timestamp used to calculate exchange rate
     * @param maturity fcash maturity used to calculate exchange rate
     * @return new fCash amount with slippage applied and the new implied rate
     */
    function interestToExchangeRate(
        int128 annualizedSlippage,
        uint256 blockTime,
        uint256 maturity
    ) internal pure returns (int256) {
        uint256 timeToMaturity = maturity - blockTime;
        /// @dev e ^ ((annualRate * timeToMaturity) / SECONDS_IN_YEAR / RATE_PRECISION) * RATE_PRECISION
        return
            toInt(
                mulFixed(
                    exp(
                        divFixed(
                            divFixed(
                                mulFixed(fromInt(annualizedSlippage), fromUInt(timeToMaturity)),
                                fromUInt(SECONDS_IN_YEAR)
                            ),
                            fromInt(RATE_PRECISION)
                        )
                    ),
                    fromInt(RATE_PRECISION)
                )
            );
    }

    /**
     * Converts an exchange rate to an annual interest rate: ln(exchangeRate) * SECONDS_IN_YEAR / timeToMaturity
     *
     * @param exchangeRate exchange rate value
     * @param blockTime block time the exchange occurs on
     * @param maturity block height when the market will mature
     * @return annualized interest rate in 1e9 precision
     */
    function exchangeToInterestRate(
        int256 exchangeRate,
        uint256 blockTime,
        uint256 maturity
    ) internal pure returns (int256) {
        uint256 timeToMaturity = maturity - blockTime;
        /// @dev ((log(exchangeRate / RATE_PRECISION) * SECONDS_IN_YEAR) / timeToMaturity) * RATE_PRECISION;
        return
            toInt(
                mulFixed(
                    divFixed(
                        mulFixed(
                            ln(divFixed(fromInt(exchangeRate), fromInt(RATE_PRECISION))),
                            fromUInt(SECONDS_IN_YEAR)
                        ),
                        fromUInt(timeToMaturity)
                    ),
                    fromInt(RATE_PRECISION)
                )
            );
    }

    /**
     * Convert signed 64.64 fixed point number into signed 64-bit integer number
     * rounding down.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64-bit integer number
     */
    function toInt(int128 x) internal pure returns (int64) {
        return int64(x >> 64);
    }

    /**
     * Convert signed 64.64 fixed point number into unsigned 64-bit integer
     * number rounding down.  Revert on underflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @return unsigned 64-bit integer number
     */
    function toUInt(int128 x) internal pure returns (uint64) {
        require(x >= 0);
        return uint64(uint128(x >> 64));
    }

    /**
     * Convert unsigned 256-bit integer number into signed 64.64-bit fixed point
     * number.  Revert on overflow.
     *
     * @param x unsigned 256-bit integer number
     * @return signed 64.64-bit fixed point number
     */
    function fromUInt(uint256 x) internal pure returns (int128) {
        require(x <= 0x7FFFFFFFFFFFFFFF);
        return int128(int256(x << 64));
    }

    /**
     * Convert signed 256-bit integer number into signed 64.64-bit fixed point
     * number.  Revert on overflow.
     *
     * @param x signed 256-bit integer number
     * @return signed 64.64-bit fixed point number
     */
    function fromInt(int256 x) internal pure returns (int128) {
        require(x >= -0x8000000000000000 && x <= 0x7FFFFFFFFFFFFFFF);
        return int128(x << 64);
    }

    /**
     * Calculate x * y rounding down.  Revert on overflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @param y signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function mulFixed(int128 x, int128 y) internal pure returns (int128) {
        int256 result = (int256(x) * y) >> 64;
        require(result >= MIN_64x64 && result <= MAX_64x64);
        return int128(result);
    }

    /**
     * Calculate x / y rounding towards zero.  Revert on overflow or when y is
     * zero.
     *
     * @param x signed 64.64-bit fixed point number
     * @param y signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function divFixed(int128 x, int128 y) internal pure returns (int128) {
        require(y != 0);
        int256 result = (int256(x) << 64) / y;
        require(result >= MIN_64x64 && result <= MAX_64x64);
        return int128(result);
    }

    function encodeLendTrade(
        uint8 marketIndex,
        int256 fCashAmount,
        int256 minLendRate
    ) internal pure returns (bytes32) {
        require(fCashAmount >= 0 && uint256(fCashAmount) <= type(uint88).max, "Invalid fCashAmount");
        require(minLendRate >= 0 && uint256(minLendRate) <= type(uint32).max, "Invalid minLendRate");

        return
            (bytes32(uint256(LEND_TRADE)) << 248) |
            (bytes32(uint256(marketIndex)) << 240) |
            (bytes32(uint256(fCashAmount)) << 152) |
            (bytes32(uint256(minLendRate)) << 120);
    }

    function encodeBorrowTrade(
        uint8 marketIndex,
        int256 fCashAmount,
        int256 maxBorrowRate
    ) internal pure returns (bytes32) {
        require(fCashAmount >= 0 && uint256(fCashAmount) <= type(uint88).max, "Invalid fCashAmount");
        require(maxBorrowRate >= 0 && uint256(maxBorrowRate) <= type(uint32).max, "Invalid maxBorrowRate");

        return
            (bytes32(uint256(BORROW_TRADE)) << 248) |
            (bytes32(uint256(marketIndex)) << 240) |
            (bytes32(uint256(fCashAmount)) << 152) |
            (bytes32(uint256(maxBorrowRate)) << 120);
    }
}
