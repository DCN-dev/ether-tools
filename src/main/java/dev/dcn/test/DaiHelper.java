package dev.dcn.test;

import java.math.BigDecimal;
import java.math.BigInteger;

public class DaiHelper {
    public static final BigInteger DAI_UNIT = BigInteger.TEN.pow(18);
    public static final BigDecimal DAI_UNIT_BIG = new BigDecimal(DAI_UNIT);

    public static BigInteger DaiAmount(String amount) {
        return new BigDecimal(amount).multiply(DAI_UNIT_BIG).toBigIntegerExact();
    }

    public static BigInteger cDaiAmount(String daiAmount, BigInteger rate) {
        return DaiAmount(daiAmount).multiply(DAI_UNIT).divide(rate);
    }

    public static String DaiString(BigInteger amount) {
        return new BigDecimal(amount).divide(DAI_UNIT_BIG, 18, 0).toPlainString();
    }
}
