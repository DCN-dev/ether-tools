package dev.dcn.ether_net;

import org.web3j.protocol.Web3j;

import java.io.Closeable;

public interface Web3Provider extends Closeable {
    Web3j web3();
}
