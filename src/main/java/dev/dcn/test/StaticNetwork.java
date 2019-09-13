package dev.dcn.test;

import dev.dcn.ether_net.EtherDebugNet;
import org.web3j.crypto.Credentials;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterNumber;
import org.web3j.protocol.core.methods.response.EthBlockNumber;

import java.io.IOException;
import java.math.BigInteger;
import java.util.HashMap;
import java.util.Stack;

public class StaticNetwork {
    public static final BigInteger GAS_LIMIT = BigInteger.valueOf(8000000);
    private static EtherDebugNet network = null;

    public static void Start() {
        try {
            HashMap<String, String> accounts = new HashMap<>();
            for (Credentials key : Accounts.keys) {
                accounts.put(key.getEcKeyPair().getPrivateKey().toString(16), "1000000000000000000000000000000000");
            }

            network = new EtherDebugNet(5123, "localhost", accounts, 8000000, 9999);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }

        Runtime.getRuntime().addShutdownHook(new Thread(network::close));
    }

    public static Web3j Web3() {
        return network.web3();
    }

    public static BigInteger GetBalance(String address) throws IOException {
        EthBlockNumber block = StaticNetwork.Web3().ethBlockNumber().send();
        return Web3().ethGetBalance(address, new DefaultBlockParameterNumber(block.getBlockNumber())).send().getBalance();
    }

    private static final Stack<BigInteger> checkpoints = new Stack<>();

    public static void Checkpoint() {
        try {
            checkpoints.push(network.checkpoint().send().id());
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    public static void Revert() {
        try {
            network.revert(checkpoints.pop()).send();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    public static long IncreaseTime(long seconds) throws IOException {
        return network.increaseTime(BigInteger.valueOf(seconds)).send().getValue().longValueExact();
    }
}
