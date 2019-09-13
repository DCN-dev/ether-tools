package dev.dcn;

import dev.dcn.web3.PersonalSign;
import org.agrona.concurrent.UnsafeBuffer;
import org.web3j.utils.Numeric;

import java.nio.ByteOrder;

public class PaymentUpdate {
    public static final int BYTES = 3 * 4 + 1 + 32 * 2;
    private static final ByteOrder ORDER = ByteOrder.BIG_ENDIAN;


    private final byte[] data = new byte[BYTES];
    private final UnsafeBuffer buffer = new UnsafeBuffer(data);

    public PaymentUpdate() {
    }

    public PaymentUpdate updateId(int value) {
        buffer.putInt(0, value, ORDER);
        return this;
    }

    public PaymentUpdate payment(int value) {
        buffer.putInt(4, value, ORDER);
        return this;
    }

    public PaymentUpdate rate(int value) {
        buffer.putInt(8, value, ORDER);
        return this;
    }

    public int updateId() {
        return buffer.getInt(0, ORDER);
    }

    public int payment() {
        return buffer.getInt(4, ORDER);
    }

    public int rate() {
        return buffer.getInt(8, ORDER);
    }

    public void clear() {
        buffer.setMemory(0, BYTES, (byte) 0);
    }

    public String toHex() {
        return Numeric.toHexString(data);
    }

    public byte[] hash() {
        StringBuilder stringBuilder = new StringBuilder();
        stringBuilder.append("DaiDrop v1: setPayment       \n  ")
                .append("update_sequence=")
                .append(numberPad(8, updateId()))

                .append(", payment=")
                .append(numberPad(5, payment() / 100)).append(".").append(numberPad(2, payment() % 100))

                .append(", rate=")
                .append(numberPad(5, rate() / 100)).append(".").append(numberPad(2, rate() % 100));
        return PersonalSign.Hash(stringBuilder);
    }

    private static final String ZEROS = "00000000000000000000000000000000000000000000000";

    private static String numberPad(int length, int number) {
        String str = String.valueOf(number);
        if (str.length() == length) {
            return str;
        }

        if (str.length() > length) {
            throw new IllegalArgumentException();
        }

        return ZEROS.substring(0, length - str.length()) + str;
    }
}
