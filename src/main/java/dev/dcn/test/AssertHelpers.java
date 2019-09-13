package dev.dcn.test;

import dev.dcn.web3.RevertCodeExtractor;
import org.web3j.protocol.core.Response;
import org.web3j.protocol.core.methods.response.EthSendTransaction;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.protocol.exceptions.TransactionException;

import java.io.IOException;

public class AssertHelpers {
    public static TransactionReceipt assertSuccess(EthSendTransaction tx) {
        try {
            if (tx.hasError()) {
                Response.Error error = tx.getError();

                String get;
                try {
                    get = RevertCodeExtractor.GetRevert(error);
                } catch (Exception e) {
                    throw new AssertionError(
                            error.getCode() + " : " + error.getMessage() + " : " + error.getData());
                }

                throw new AssertionError("Got revert: " + get);
            }
            TransactionReceipt result = Accounts.getTx(0).waitForResult(tx);
            if (!"0x1".equals(result.getStatus())) {
                throw new AssertionError("Tx not a success, got: " + result.getStatus());
            }
            return result;
        } catch (IOException | TransactionException e) {
            throw new RuntimeException(e);
        }
    }

    public static String getRevert(EthSendTransaction tx) {
        try {
            if (!tx.hasError()) {
                throw new AssertionError("Tx did not fail");
            }
            return RevertCodeExtractor.GetRevert(tx.getError());
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public static void assertRevert(String revertMessage, EthSendTransaction tx) {
        try {
            if (!tx.hasError()) {
                throw new AssertionError("Tx did not fail");
            }
            assertEquals(revertMessage, RevertCodeExtractor.GetRevert(tx.getError()));
            assertEquals("0x0", Accounts.getTx(0).waitForResult(tx).getStatus());
        } catch (IOException | TransactionException e) {
            throw new RuntimeException(e);
        }
    }

    private static void assertEquals(String a, String b) {
        if (!a.equals(b)) {
            throw new AssertionError("Expected: " + a + ", but got: " + b);
        }
    }
}
