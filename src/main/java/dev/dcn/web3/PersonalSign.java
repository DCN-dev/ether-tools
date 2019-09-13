package dev.dcn.web3;

import dev.dcn.KeccakHash;

public class PersonalSign {
    private static final String PREFIX = "\u0019Ethereum Signed Message:\n";

    public static byte[] Hash(StringBuilder sb) {
        String toHash = PREFIX + sb.length() + sb.toString();
        return KeccakHash.Hash(toHash.getBytes());
    }
}
