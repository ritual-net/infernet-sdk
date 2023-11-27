// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Halo2Verifier {
    uint256 internal constant    PROOF_LEN_CPTR = 0x44;
    uint256 internal constant        PROOF_CPTR = 0x64;
    uint256 internal constant NUM_INSTANCE_CPTR = 0x0ce4;
    uint256 internal constant     INSTANCE_CPTR = 0x0d04;

    uint256 internal constant FIRST_QUOTIENT_X_CPTR = 0x0424;
    uint256 internal constant  LAST_QUOTIENT_X_CPTR = 0x05e4;

    uint256 internal constant                VK_MPTR = 0x06c0;
    uint256 internal constant         VK_DIGEST_MPTR = 0x06c0;
    uint256 internal constant                 K_MPTR = 0x06e0;
    uint256 internal constant             N_INV_MPTR = 0x0700;
    uint256 internal constant             OMEGA_MPTR = 0x0720;
    uint256 internal constant         OMEGA_INV_MPTR = 0x0740;
    uint256 internal constant    OMEGA_INV_TO_L_MPTR = 0x0760;
    uint256 internal constant     NUM_INSTANCES_MPTR = 0x0780;
    uint256 internal constant   HAS_ACCUMULATOR_MPTR = 0x07a0;
    uint256 internal constant        ACC_OFFSET_MPTR = 0x07c0;
    uint256 internal constant     NUM_ACC_LIMBS_MPTR = 0x07e0;
    uint256 internal constant NUM_ACC_LIMB_BITS_MPTR = 0x0800;
    uint256 internal constant              G1_X_MPTR = 0x0820;
    uint256 internal constant              G1_Y_MPTR = 0x0840;
    uint256 internal constant            G2_X_1_MPTR = 0x0860;
    uint256 internal constant            G2_X_2_MPTR = 0x0880;
    uint256 internal constant            G2_Y_1_MPTR = 0x08a0;
    uint256 internal constant            G2_Y_2_MPTR = 0x08c0;
    uint256 internal constant      NEG_S_G2_X_1_MPTR = 0x08e0;
    uint256 internal constant      NEG_S_G2_X_2_MPTR = 0x0900;
    uint256 internal constant      NEG_S_G2_Y_1_MPTR = 0x0920;
    uint256 internal constant      NEG_S_G2_Y_2_MPTR = 0x0940;

    uint256 internal constant CHALLENGE_MPTR = 0x0f60;

    uint256 internal constant THETA_MPTR = 0x0f60;
    uint256 internal constant  BETA_MPTR = 0x0f80;
    uint256 internal constant GAMMA_MPTR = 0x0fa0;
    uint256 internal constant     Y_MPTR = 0x0fc0;
    uint256 internal constant     X_MPTR = 0x0fe0;
    uint256 internal constant  ZETA_MPTR = 0x1000;
    uint256 internal constant    NU_MPTR = 0x1020;
    uint256 internal constant    MU_MPTR = 0x1040;

    uint256 internal constant       ACC_LHS_X_MPTR = 0x1060;
    uint256 internal constant       ACC_LHS_Y_MPTR = 0x1080;
    uint256 internal constant       ACC_RHS_X_MPTR = 0x10a0;
    uint256 internal constant       ACC_RHS_Y_MPTR = 0x10c0;
    uint256 internal constant             X_N_MPTR = 0x10e0;
    uint256 internal constant X_N_MINUS_1_INV_MPTR = 0x1100;
    uint256 internal constant          L_LAST_MPTR = 0x1120;
    uint256 internal constant         L_BLIND_MPTR = 0x1140;
    uint256 internal constant             L_0_MPTR = 0x1160;
    uint256 internal constant   INSTANCE_EVAL_MPTR = 0x1180;
    uint256 internal constant   QUOTIENT_EVAL_MPTR = 0x11a0;
    uint256 internal constant      QUOTIENT_X_MPTR = 0x11c0;
    uint256 internal constant      QUOTIENT_Y_MPTR = 0x11e0;
    uint256 internal constant          R_EVAL_MPTR = 0x1200;
    uint256 internal constant   PAIRING_LHS_X_MPTR = 0x1220;
    uint256 internal constant   PAIRING_LHS_Y_MPTR = 0x1240;
    uint256 internal constant   PAIRING_RHS_X_MPTR = 0x1260;
    uint256 internal constant   PAIRING_RHS_Y_MPTR = 0x1280;

    function verifyProof(
        bytes calldata proof,
        uint256[] calldata instances
    ) public returns (bool) {
        assembly {
            // Read EC point (x, y) at (proof_cptr, proof_cptr + 0x20),
            // and check if the point is on affine plane,
            // and store them in (hash_mptr, hash_mptr + 0x20).
            // Return updated (success, proof_cptr, hash_mptr).
            function read_ec_point(success, proof_cptr, hash_mptr, q) -> ret0, ret1, ret2 {
                let x := calldataload(proof_cptr)
                let y := calldataload(add(proof_cptr, 0x20))
                ret0 := and(success, lt(x, q))
                ret0 := and(ret0, lt(y, q))
                ret0 := and(ret0, eq(mulmod(y, y, q), addmod(mulmod(x, mulmod(x, x, q), q), 3, q)))
                mstore(hash_mptr, x)
                mstore(add(hash_mptr, 0x20), y)
                ret1 := add(proof_cptr, 0x40)
                ret2 := add(hash_mptr, 0x40)
            }

            // Squeeze challenge by keccak256(memory[0..hash_mptr]),
            // and store hash mod r as challenge in challenge_mptr,
            // and push back hash in 0x00 as the first input for next squeeze.
            // Return updated (challenge_mptr, hash_mptr).
            function squeeze_challenge(challenge_mptr, hash_mptr, r) -> ret0, ret1 {
                let hash := keccak256(0x00, hash_mptr)
                mstore(challenge_mptr, mod(hash, r))
                mstore(0x00, hash)
                ret0 := add(challenge_mptr, 0x20)
                ret1 := 0x20
            }

            // Squeeze challenge without absorbing new input from calldata,
            // by putting an extra 0x01 in memory[0x20] and squeeze by keccak256(memory[0..21]),
            // and store hash mod r as challenge in challenge_mptr,
            // and push back hash in 0x00 as the first input for next squeeze.
            // Return updated (challenge_mptr).
            function squeeze_challenge_cont(challenge_mptr, r) -> ret {
                mstore8(0x20, 0x01)
                let hash := keccak256(0x00, 0x21)
                mstore(challenge_mptr, mod(hash, r))
                mstore(0x00, hash)
                ret := add(challenge_mptr, 0x20)
            }

            // Batch invert values in memory[mptr_start..mptr_end] in place.
            // Return updated (success).
            function batch_invert(success, mptr_start, mptr_end, r) -> ret {
                let gp_mptr := mptr_end
                let gp := mload(mptr_start)
                let mptr := add(mptr_start, 0x20)
                for
                    {}
                    lt(mptr, sub(mptr_end, 0x20))
                    {}
                {
                    gp := mulmod(gp, mload(mptr), r)
                    mstore(gp_mptr, gp)
                    mptr := add(mptr, 0x20)
                    gp_mptr := add(gp_mptr, 0x20)
                }
                gp := mulmod(gp, mload(mptr), r)

                mstore(gp_mptr, 0x20)
                mstore(add(gp_mptr, 0x20), 0x20)
                mstore(add(gp_mptr, 0x40), 0x20)
                mstore(add(gp_mptr, 0x60), gp)
                mstore(add(gp_mptr, 0x80), sub(r, 2))
                mstore(add(gp_mptr, 0xa0), r)
                ret := and(success, staticcall(gas(), 0x05, gp_mptr, 0xc0, gp_mptr, 0x20))
                let all_inv := mload(gp_mptr)

                let first_mptr := mptr_start
                let second_mptr := add(first_mptr, 0x20)
                gp_mptr := sub(gp_mptr, 0x20)
                for
                    {}
                    lt(second_mptr, mptr)
                    {}
                {
                    let inv := mulmod(all_inv, mload(gp_mptr), r)
                    all_inv := mulmod(all_inv, mload(mptr), r)
                    mstore(mptr, inv)
                    mptr := sub(mptr, 0x20)
                    gp_mptr := sub(gp_mptr, 0x20)
                }
                let inv_first := mulmod(all_inv, mload(second_mptr), r)
                let inv_second := mulmod(all_inv, mload(first_mptr), r)
                mstore(first_mptr, inv_first)
                mstore(second_mptr, inv_second)
            }

            // Add (x, y) into point at (0x00, 0x20).
            // Return updated (success).
            function ec_add_acc(success, x, y) -> ret {
                mstore(0x40, x)
                mstore(0x60, y)
                ret := and(success, staticcall(gas(), 0x06, 0x00, 0x80, 0x00, 0x40))
            }

            // Scale point at (0x00, 0x20) by scalar.
            function ec_mul_acc(success, scalar) -> ret {
                mstore(0x40, scalar)
                ret := and(success, staticcall(gas(), 0x07, 0x00, 0x60, 0x00, 0x40))
            }

            // Add (x, y) into point at (0x80, 0xa0).
            // Return updated (success).
            function ec_add_tmp(success, x, y) -> ret {
                mstore(0xc0, x)
                mstore(0xe0, y)
                ret := and(success, staticcall(gas(), 0x06, 0x80, 0x80, 0x80, 0x40))
            }

            // Scale point at (0x80, 0xa0) by scalar.
            // Return updated (success).
            function ec_mul_tmp(success, scalar) -> ret {
                mstore(0xc0, scalar)
                ret := and(success, staticcall(gas(), 0x07, 0x80, 0x60, 0x80, 0x40))
            }

            // Perform pairing check.
            // Return updated (success).
            function ec_pairing(success, lhs_x, lhs_y, rhs_x, rhs_y) -> ret {
                mstore(0x00, lhs_x)
                mstore(0x20, lhs_y)
                mstore(0x40, mload(G2_X_1_MPTR))
                mstore(0x60, mload(G2_X_2_MPTR))
                mstore(0x80, mload(G2_Y_1_MPTR))
                mstore(0xa0, mload(G2_Y_2_MPTR))
                mstore(0xc0, rhs_x)
                mstore(0xe0, rhs_y)
                mstore(0x100, mload(NEG_S_G2_X_1_MPTR))
                mstore(0x120, mload(NEG_S_G2_X_2_MPTR))
                mstore(0x140, mload(NEG_S_G2_Y_1_MPTR))
                mstore(0x160, mload(NEG_S_G2_Y_2_MPTR))
                ret := and(success, staticcall(gas(), 0x08, 0x00, 0x180, 0x00, 0x20))
                ret := and(ret, mload(0x00))
            }

            // Modulus
            let q := 21888242871839275222246405745257275088696311157297823662689037894645226208583 // BN254 base field
            let r := 21888242871839275222246405745257275088548364400416034343698204186575808495617 // BN254 scalar field

            // Initialize success as true
            let success := true

            {
                // Load vk into memory
                mstore(0x06c0, 0x0ae5a4c87fb4103b0474b36e02a3098cfd57ce027aa1127070f9f37f5cada089) // vk_digest
                mstore(0x06e0, 0x0000000000000000000000000000000000000000000000000000000000000010) // k
                mstore(0x0700, 0x30641e0e92bebef818268d663bcad6dbcfd6c0149170f6d7d350b1b1fa6c1001) // n_inv
                mstore(0x0720, 0x09d2cc4b5782fbe923e49ace3f647643a5f5d8fb89091c3ababd582133584b29) // omega
                mstore(0x0740, 0x0cf312e84f2456134e812826473d3dfb577b2bfdba762aba88b47b740472c1f0) // omega_inv
                mstore(0x0760, 0x17cbd779ed6ea1b8e9dbcde0345b2cfdb96e80bea0dd1318bdd0e183a00e0492) // omega_inv_to_l
                mstore(0x0780, 0x0000000000000000000000000000000000000000000000000000000000000002) // num_instances
                mstore(0x07a0, 0x0000000000000000000000000000000000000000000000000000000000000000) // has_accumulator
                mstore(0x07c0, 0x0000000000000000000000000000000000000000000000000000000000000000) // acc_offset
                mstore(0x07e0, 0x0000000000000000000000000000000000000000000000000000000000000000) // num_acc_limbs
                mstore(0x0800, 0x0000000000000000000000000000000000000000000000000000000000000000) // num_acc_limb_bits
                mstore(0x0820, 0x0000000000000000000000000000000000000000000000000000000000000001) // g1_x
                mstore(0x0840, 0x0000000000000000000000000000000000000000000000000000000000000002) // g1_y
                mstore(0x0860, 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2) // g2_x_1
                mstore(0x0880, 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed) // g2_x_2
                mstore(0x08a0, 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b) // g2_y_1
                mstore(0x08c0, 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa) // g2_y_2
                mstore(0x08e0, 0x186282957db913abd99f91db59fe69922e95040603ef44c0bd7aa3adeef8f5ac) // neg_s_g2_x_1
                mstore(0x0900, 0x17944351223333f260ddc3b4af45191b856689eda9eab5cbcddbbe570ce860d2) // neg_s_g2_x_2
                mstore(0x0920, 0x06d971ff4a7467c3ec596ed6efc674572e32fd6f52b721f97e35b0b3d3546753) // neg_s_g2_y_1
                mstore(0x0940, 0x06ecdb9f9567f59ed2eee36e1e1d58797fd13cc97fafc2910f5e8a12f202fa9a) // neg_s_g2_y_2
                mstore(0x0960, 0x210158638dee451e534ca110fc31daf414782bec22ace8deda119e2973873bc1) // fixed_comms[0].x
                mstore(0x0980, 0x241019be3d408241c697fe490965af44c0359262b017371a9323e30c496564b4) // fixed_comms[0].y
                mstore(0x09a0, 0x29e8e775ce84508305d23a5baf9e7221a162af2702fc6defe9866e45bb4bbcd9) // fixed_comms[1].x
                mstore(0x09c0, 0x08c60ca3c56df01dc9bec33189e4689b04023002d24b67d057cb258f585ee564) // fixed_comms[1].y
                mstore(0x09e0, 0x2fa37d05e9d3dae99a6aae909d08ec31ff241bc5f66eb2ff132ef36e3ed98099) // fixed_comms[2].x
                mstore(0x0a00, 0x15fc9b4a39f85774b22344bbdedc9cf7008fb687a123746b19286793ed75cca3) // fixed_comms[2].y
                mstore(0x0a20, 0x1f064961101aac429edf8abc2ef15cc130e75f51b7f3a2c46940e65ae93b201d) // fixed_comms[3].x
                mstore(0x0a40, 0x03524af19a65d5b32cc6060fce0d53229180ff08041bf3c7aefdb70878e76200) // fixed_comms[3].y
                mstore(0x0a60, 0x0c8b6487a2f59fd7e1d1f3988f61bab968a4d1061f2666b08591b677f1258f62) // fixed_comms[4].x
                mstore(0x0a80, 0x2c675bb5db47e0a6a65b7df8396c44faa4ebe44dadf93e5130b9f97682c34395) // fixed_comms[4].y
                mstore(0x0aa0, 0x2cdd59160fb54c7952431f7e0a8ef998dd48ca772ea89c51cb8b0ba45d2405aa) // fixed_comms[5].x
                mstore(0x0ac0, 0x1dc088b956d7fcbd917ca8a5fa2e246e7563a15754c10183ad99098930a6278a) // fixed_comms[5].y
                mstore(0x0ae0, 0x2490aa617abc1bb6328ccc836f0aba10993b4521eac94709c9f6b67de36ebfe3) // fixed_comms[6].x
                mstore(0x0b00, 0x0c3215edaf5e3f4eb69ac2d2b617c5a966489df89f1fc0e46f381377ffcfd68c) // fixed_comms[6].y
                mstore(0x0b20, 0x2032d5131dee7fe76191b84e49a98f07646f904f24637350b1395ef132d7517b) // fixed_comms[7].x
                mstore(0x0b40, 0x2627d23016719c05b2ce555e4dfc2b7fa30c124c594648d8bfa2ae5a750f261e) // fixed_comms[7].y
                mstore(0x0b60, 0x25c735898c41a6be70972861480d514a320b949f8913b5e4d161fc750acafa08) // fixed_comms[8].x
                mstore(0x0b80, 0x02d16a0d959e7cc34a3996bc14e6ff9dab8bcf9bb825a2e9ac22e17fac3b49ca) // fixed_comms[8].y
                mstore(0x0ba0, 0x070579580ec1629f98a8811ba4d83445315216338f6c38cb8592aab5b1e271e9) // fixed_comms[9].x
                mstore(0x0bc0, 0x01f68299fc5e0efa355203f4434e9f66989580084adbf24bf5d793718eeaae1b) // fixed_comms[9].y
                mstore(0x0be0, 0x2ace5e4438d8115a669f3336e61bfd1a89f69c7422a9cd34dfd108160a9923db) // fixed_comms[10].x
                mstore(0x0c00, 0x11d91245b34a6a9f5764157f1018fcb2fe90792063a0eb8774c545df09f2688c) // fixed_comms[10].y
                mstore(0x0c20, 0x22c96a7591c2f6edfbfa178152a68b018b71eec65ec208eb6e2bbf91a4945a79) // fixed_comms[11].x
                mstore(0x0c40, 0x214a80d1b409978948041daa3cc2eecdafe649277c703e9589d3007ca58973b5) // fixed_comms[11].y
                mstore(0x0c60, 0x1a601b7f675c4fe73fe0bf9918f89cb969bd3040d57e9504b34e655175c67410) // fixed_comms[12].x
                mstore(0x0c80, 0x26f1947f802dba63b59e6c04136ac05291b7e16d722624c17cfcc770239f2e8e) // fixed_comms[12].y
                mstore(0x0ca0, 0x119e73e1a59373a98f488ee84c48656268297e0505746cd80c37263242c34936) // fixed_comms[13].x
                mstore(0x0cc0, 0x179c386c3700be5d23f4eeb24f00a0f8472555a8d1f1a7eff95baeeeaef9e70b) // fixed_comms[13].y
                mstore(0x0ce0, 0x112d52058b92c0d9aa456b67fe453e0981a5553569f87d5ba7102973bd0d33de) // fixed_comms[14].x
                mstore(0x0d00, 0x0f2682ed5aca4f8d0602c2dce2f50df6888903213c5157f9ae2713d9bfe465ec) // fixed_comms[14].y
                mstore(0x0d20, 0x2c440cbc47a5bbff677fc24d1281ac43d61a62fcbd1caa4085a37a088f79a926) // permutation_comms[0].x
                mstore(0x0d40, 0x2315ddf7620b6aa6b478d24ad2e968eda3829d03d1bf1bf0174c19dba75be88e) // permutation_comms[0].y
                mstore(0x0d60, 0x0ffeb7fbdfdc7aab4eec03154891297394e3e3649f398e349476651371b4067d) // permutation_comms[1].x
                mstore(0x0d80, 0x2ecff97abf5acfe64c9e69fd28922c718357a7e13efee5227384f3753eb869e5) // permutation_comms[1].y
                mstore(0x0da0, 0x044ac3fb938c1db4c36700f4409178241f6e4a9e68e207b2d6637748b1cc67cf) // permutation_comms[2].x
                mstore(0x0dc0, 0x1de04e04cbc29e79f7d9207c362a7b426037067d8bd9f08887c37b9cf6b60999) // permutation_comms[2].y
                mstore(0x0de0, 0x0b1851f4bf6f1f521924f5a96c12ed415b10ea76b9328ba2f63e29897ed90229) // permutation_comms[3].x
                mstore(0x0e00, 0x11b40547dbdf4da6b179398f058e3b0cbe820088f72df45d8da0f6ba8f215bce) // permutation_comms[3].y
                mstore(0x0e20, 0x12ea0919232cd844421c9228f7e6703d0d699b7e4cea4c2dc4db54c2254dc817) // permutation_comms[4].x
                mstore(0x0e40, 0x2b462d68c894d2a421d5243cf88c291138131a0e49d97ec8b01ceb3121e35c99) // permutation_comms[4].y
                mstore(0x0e60, 0x28103ab59e64b227f453fdf78adb3582f1d0782f3ee84fcca940aeb46853d0a1) // permutation_comms[5].x
                mstore(0x0e80, 0x1581f7cc3103852df74d7fb9ea86b6912669f4233dbc144ec2283505a18fe12b) // permutation_comms[5].y
                mstore(0x0ea0, 0x0a7996aa36917b2d360c2b7483d55745e68081d52528c518c61e34ae6ae959de) // permutation_comms[6].x
                mstore(0x0ec0, 0x0008bebe37e9ab56bb961edd911f65d07f60860309390fe53e4d0b0894b8ea42) // permutation_comms[6].y
                mstore(0x0ee0, 0x2cd17e5f3e3e213aa5d5f906882690d71254aa1d72e37c60a95c1a9eaad90239) // permutation_comms[7].x
                mstore(0x0f00, 0x0bbef341c6c6abea51c9eadf42304f6328fad70bdd0ad2b848bacfcb1990bcc1) // permutation_comms[7].y
                mstore(0x0f20, 0x01a7837e6470babb230978a3079af34e382588caaf1c0c791e81f37222798929) // permutation_comms[8].x
                mstore(0x0f40, 0x155c9bea95acf37b018196229c82254163940010ab902b96a4dcde67c6a99a6f) // permutation_comms[8].y

                // Check valid length of proof
                success := and(success, eq(0x0c80, calldataload(PROOF_LEN_CPTR)))

                // Check valid length of instances
                let num_instances := mload(NUM_INSTANCES_MPTR)
                success := and(success, eq(num_instances, calldataload(NUM_INSTANCE_CPTR)))

                // Absorb vk diegst
                mstore(0x00, mload(VK_DIGEST_MPTR))

                // Read instances and witness commitments and generate challenges
                let hash_mptr := 0x20
                let instance_cptr := INSTANCE_CPTR
                for
                    { let instance_cptr_end := add(instance_cptr, mul(0x20, num_instances)) }
                    lt(instance_cptr, instance_cptr_end)
                    {}
                {
                    let instance := calldataload(instance_cptr)
                    success := and(success, lt(instance, r))
                    mstore(hash_mptr, instance)
                    instance_cptr := add(instance_cptr, 0x20)
                    hash_mptr := add(hash_mptr, 0x20)
                }

                let proof_cptr := PROOF_CPTR
                let challenge_mptr := CHALLENGE_MPTR

                // Phase 1
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0180) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Phase 2
                for
                    { let proof_cptr_end := add(proof_cptr, 0xc0) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)
                challenge_mptr := squeeze_challenge_cont(challenge_mptr, r)

                // Phase 3
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0180) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Phase 4
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0200) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Read evaluations
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0640) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    let eval := calldataload(proof_cptr)
                    success := and(success, lt(eval, r))
                    mstore(hash_mptr, eval)
                    proof_cptr := add(proof_cptr, 0x20)
                    hash_mptr := add(hash_mptr, 0x20)
                }

                // Read batch opening proof and generate challenges
                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)       // zeta
                challenge_mptr := squeeze_challenge_cont(challenge_mptr, r)                        // nu

                success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q) // W

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)       // mu

                success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q) // W'

                // Read accumulator from instances
                if mload(HAS_ACCUMULATOR_MPTR) {
                    let num_limbs := mload(NUM_ACC_LIMBS_MPTR)
                    let num_limb_bits := mload(NUM_ACC_LIMB_BITS_MPTR)

                    let cptr := add(INSTANCE_CPTR, mul(mload(ACC_OFFSET_MPTR), 0x20))
                    let lhs_y_off := mul(num_limbs, 0x20)
                    let rhs_x_off := mul(lhs_y_off, 2)
                    let rhs_y_off := mul(lhs_y_off, 3)
                    let lhs_x := calldataload(cptr)
                    let lhs_y := calldataload(add(cptr, lhs_y_off))
                    let rhs_x := calldataload(add(cptr, rhs_x_off))
                    let rhs_y := calldataload(add(cptr, rhs_y_off))
                    for
                        {
                            let cptr_end := add(cptr, mul(0x20, num_limbs))
                            let shift := num_limb_bits
                        }
                        lt(cptr, cptr_end)
                        {}
                    {
                        cptr := add(cptr, 0x20)
                        lhs_x := add(lhs_x, shl(shift, calldataload(cptr)))
                        lhs_y := add(lhs_y, shl(shift, calldataload(add(cptr, lhs_y_off))))
                        rhs_x := add(rhs_x, shl(shift, calldataload(add(cptr, rhs_x_off))))
                        rhs_y := add(rhs_y, shl(shift, calldataload(add(cptr, rhs_y_off))))
                        shift := add(shift, num_limb_bits)
                    }

                    success := and(success, eq(mulmod(lhs_y, lhs_y, q), addmod(mulmod(lhs_x, mulmod(lhs_x, lhs_x, q), q), 3, q)))
                    success := and(success, eq(mulmod(rhs_y, rhs_y, q), addmod(mulmod(rhs_x, mulmod(rhs_x, rhs_x, q), q), 3, q)))

                    mstore(ACC_LHS_X_MPTR, lhs_x)
                    mstore(ACC_LHS_Y_MPTR, lhs_y)
                    mstore(ACC_RHS_X_MPTR, rhs_x)
                    mstore(ACC_RHS_Y_MPTR, rhs_y)
                }

                pop(q)
            }

            // Revert earlier if anything from calldata is invalid
            if iszero(success) {
                revert(0, 0)
            }

            // Compute lagrange evaluations and instance evaluation
            {
                let k := mload(K_MPTR)
                let x := mload(X_MPTR)
                let x_n := x
                for
                    { let idx := 0 }
                    lt(idx, k)
                    { idx := add(idx, 1) }
                {
                    x_n := mulmod(x_n, x_n, r)
                }

                let omega := mload(OMEGA_MPTR)

                let mptr := X_N_MPTR
                let mptr_end := add(mptr, mul(0x20, add(mload(NUM_INSTANCES_MPTR), 6)))
                for
                    { let pow_of_omega := mload(OMEGA_INV_TO_L_MPTR) }
                    lt(mptr, mptr_end)
                    { mptr := add(mptr, 0x20) }
                {
                    mstore(mptr, addmod(x, sub(r, pow_of_omega), r))
                    pow_of_omega := mulmod(pow_of_omega, omega, r)
                }
                let x_n_minus_1 := addmod(x_n, sub(r, 1), r)
                mstore(mptr_end, x_n_minus_1)
                success := batch_invert(success, X_N_MPTR, add(mptr_end, 0x20), r)

                mptr := X_N_MPTR
                let l_i_common := mulmod(x_n_minus_1, mload(N_INV_MPTR), r)
                for
                    { let pow_of_omega := mload(OMEGA_INV_TO_L_MPTR) }
                    lt(mptr, mptr_end)
                    { mptr := add(mptr, 0x20) }
                {
                    mstore(mptr, mulmod(l_i_common, mulmod(mload(mptr), pow_of_omega, r), r))
                    pow_of_omega := mulmod(pow_of_omega, omega, r)
                }

                let l_blind := mload(add(X_N_MPTR, 0x20))
                let l_i_cptr := add(X_N_MPTR, 0x40)
                for
                    { let l_i_cptr_end := add(X_N_MPTR, 0xc0) }
                    lt(l_i_cptr, l_i_cptr_end)
                    { l_i_cptr := add(l_i_cptr, 0x20) }
                {
                    l_blind := addmod(l_blind, mload(l_i_cptr), r)
                }

                let instance_eval := mulmod(mload(l_i_cptr), calldataload(INSTANCE_CPTR), r)
                let instance_cptr := add(INSTANCE_CPTR, 0x20)
                l_i_cptr := add(l_i_cptr, 0x20)
                for
                    { let instance_cptr_end := add(INSTANCE_CPTR, mul(0x20, mload(NUM_INSTANCES_MPTR))) }
                    lt(instance_cptr, instance_cptr_end)
                    {
                        instance_cptr := add(instance_cptr, 0x20)
                        l_i_cptr := add(l_i_cptr, 0x20)
                    }
                {
                    instance_eval := addmod(instance_eval, mulmod(mload(l_i_cptr), calldataload(instance_cptr), r), r)
                }

                let x_n_minus_1_inv := mload(mptr_end)
                let l_last := mload(X_N_MPTR)
                let l_0 := mload(add(X_N_MPTR, 0xc0))

                mstore(X_N_MPTR, x_n)
                mstore(X_N_MINUS_1_INV_MPTR, x_n_minus_1_inv)
                mstore(L_LAST_MPTR, l_last)
                mstore(L_BLIND_MPTR, l_blind)
                mstore(L_0_MPTR, l_0)
                mstore(INSTANCE_EVAL_MPTR, instance_eval)
            }

            // Compute quotient evavluation
            {
                let quotient_eval_numer
                let delta := 4131629893567559867359510883348571134090853742863529169391034518566172092834
                let y := mload(Y_MPTR)
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x2
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_3 := calldataload(0x0684)
                    let f_1 := calldataload(0x07e4)
                    let var10 := addmod(a_3, f_1, r)
                    let var11 := mulmod(var10, var10, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var10, r)
                    let var14 := mulmod(var13, 0x066f6f85d6f68a85ec10345351a23a3aaf07f38af8c952a7bceca70bd2af7ad5, r)
                    let a_4 := calldataload(0x06a4)
                    let f_2 := calldataload(0x0804)
                    let var15 := addmod(a_4, f_2, r)
                    let var16 := mulmod(var15, var15, r)
                    let var17 := mulmod(var16, var16, r)
                    let var18 := mulmod(var17, var15, r)
                    let var19 := mulmod(var18, 0x2b9d4b4110c9ae997782e1509b1d0fdb20a7c02bbd8bea7305462b9f8125b1e8, r)
                    let var20 := addmod(var14, var19, r)
                    let a_3_next_1 := calldataload(0x06c4)
                    let var21 := sub(r, a_3_next_1)
                    let var22 := addmod(var20, var21, r)
                    let var23 := mulmod(var9, var22, r)
                    quotient_eval_numer := var23
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x2
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_3 := calldataload(0x0684)
                    let f_1 := calldataload(0x07e4)
                    let var10 := addmod(a_3, f_1, r)
                    let var11 := mulmod(var10, var10, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var10, r)
                    let var14 := mulmod(var13, 0x0cc57cdbb08507d62bf67a4493cc262fb6c09d557013fff1f573f431221f8ff9, r)
                    let a_4 := calldataload(0x06a4)
                    let f_2 := calldataload(0x0804)
                    let var15 := addmod(a_4, f_2, r)
                    let var16 := mulmod(var15, var15, r)
                    let var17 := mulmod(var16, var16, r)
                    let var18 := mulmod(var17, var15, r)
                    let var19 := mulmod(var18, 0x1274e649a32ed355a31a6ed69724e1adade857e86eb5c3a121bcd147943203c8, r)
                    let var20 := addmod(var14, var19, r)
                    let a_4_next_1 := calldataload(0x06e4)
                    let var21 := sub(r, a_4_next_1)
                    let var22 := addmod(var20, var21, r)
                    let var23 := mulmod(var9, var22, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var23, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_3 := calldataload(0x0684)
                    let f_1 := calldataload(0x07e4)
                    let var10 := addmod(a_3, f_1, r)
                    let var11 := mulmod(var10, var10, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var10, r)
                    let a_5 := calldataload(0x0704)
                    let var14 := sub(r, a_5)
                    let var15 := addmod(var13, var14, r)
                    let var16 := mulmod(var9, var15, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var16, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_5 := calldataload(0x0704)
                    let var10 := mulmod(a_5, 0x066f6f85d6f68a85ec10345351a23a3aaf07f38af8c952a7bceca70bd2af7ad5, r)
                    let a_4 := calldataload(0x06a4)
                    let f_2 := calldataload(0x0804)
                    let var11 := addmod(a_4, f_2, r)
                    let var12 := mulmod(var11, 0x2b9d4b4110c9ae997782e1509b1d0fdb20a7c02bbd8bea7305462b9f8125b1e8, r)
                    let var13 := addmod(var10, var12, r)
                    let f_3 := calldataload(0x07a4)
                    let var14 := addmod(var13, f_3, r)
                    let var15 := mulmod(var14, var14, r)
                    let var16 := mulmod(var15, var15, r)
                    let var17 := mulmod(var16, var14, r)
                    let a_3_next_1 := calldataload(0x06c4)
                    let var18 := mulmod(a_3_next_1, 0x13abec390ada7f4370819ab1c7846f210554569d9b29d1ea8dbebd0fa8c53e66, r)
                    let a_4_next_1 := calldataload(0x06e4)
                    let var19 := mulmod(a_4_next_1, 0x1eb9e1dc19a33a624c9862a1d97d1510bd521ead5dfe0345aaf6185b1a1e60fe, r)
                    let var20 := addmod(var18, var19, r)
                    let var21 := sub(r, var20)
                    let var22 := addmod(var17, var21, r)
                    let var23 := mulmod(var9, var22, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var23, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_5 := calldataload(0x0704)
                    let var10 := mulmod(a_5, 0x0cc57cdbb08507d62bf67a4493cc262fb6c09d557013fff1f573f431221f8ff9, r)
                    let a_4 := calldataload(0x06a4)
                    let f_2 := calldataload(0x0804)
                    let var11 := addmod(a_4, f_2, r)
                    let var12 := mulmod(var11, 0x1274e649a32ed355a31a6ed69724e1adade857e86eb5c3a121bcd147943203c8, r)
                    let var13 := addmod(var10, var12, r)
                    let f_4 := calldataload(0x07c4)
                    let var14 := addmod(var13, f_4, r)
                    let a_3_next_1 := calldataload(0x06c4)
                    let var15 := mulmod(a_3_next_1, 0x0fc1c9394db89bb2601abc49fdad4f038ce5169030a2ad69763f7875036bcb02, r)
                    let a_4_next_1 := calldataload(0x06e4)
                    let var16 := mulmod(a_4_next_1, 0x16a9e98c493a902b9502054edc03e7b22b7eac34345961bc8abced6bd147c8be, r)
                    let var17 := addmod(var15, var16, r)
                    let var18 := sub(r, var17)
                    let var19 := addmod(var14, var18, r)
                    let var20 := mulmod(var9, var19, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var20, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_3_prev_1 := calldataload(0x0744)
                    let a_3 := calldataload(0x0684)
                    let var10 := addmod(a_3_prev_1, a_3, r)
                    let a_3_next_1 := calldataload(0x06c4)
                    let var11 := sub(r, a_3_next_1)
                    let var12 := addmod(var10, var11, r)
                    let var13 := mulmod(var9, var12, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var13, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_4_prev_1 := calldataload(0x0724)
                    let a_4_next_1 := calldataload(0x06e4)
                    let var10 := sub(r, a_4_next_1)
                    let var11 := addmod(a_4_prev_1, var10, r)
                    let var12 := mulmod(var9, var11, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var12, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x5
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x6
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_0 := calldataload(0x0624)
                    let a_1 := calldataload(0x0644)
                    let var19 := mulmod(a_0, a_1, r)
                    let a_2_prev_1 := calldataload(0x0764)
                    let var20 := addmod(var19, a_2_prev_1, r)
                    let var21 := sub(r, var20)
                    let var22 := addmod(a_2, var21, r)
                    let var23 := mulmod(var18, var22, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var23, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x5
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x6
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_1 := calldataload(0x0644)
                    let a_2_prev_1 := calldataload(0x0764)
                    let var19 := mulmod(a_1, a_2_prev_1, r)
                    let var20 := sub(r, var19)
                    let var21 := addmod(a_2, var20, r)
                    let var22 := mulmod(var18, var21, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var22, r)
                }
                {
                    let f_14 := calldataload(0x0944)
                    let var0 := 0x2
                    let var1 := sub(r, f_14)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_14, var2, r)
                    let a_2 := calldataload(0x0664)
                    let a_1 := calldataload(0x0644)
                    let var4 := sub(r, a_1)
                    let var5 := addmod(a_2, var4, r)
                    let var6 := mulmod(var3, var5, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var6, r)
                }
                {
                    let f_12 := calldataload(0x0904)
                    let var0 := 0x1
                    let var1 := sub(r, f_12)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_12, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x3
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let a_2 := calldataload(0x0664)
                    let a_0 := calldataload(0x0624)
                    let a_1 := calldataload(0x0644)
                    let var10 := addmod(a_0, a_1, r)
                    let var11 := sub(r, var10)
                    let var12 := addmod(a_2, var11, r)
                    let var13 := mulmod(var9, var12, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var13, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x3
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x4
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x5
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_0 := calldataload(0x0624)
                    let a_1 := calldataload(0x0644)
                    let var19 := mulmod(a_0, a_1, r)
                    let var20 := sub(r, var19)
                    let var21 := addmod(a_2, var20, r)
                    let var22 := mulmod(var18, var21, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var22, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x2
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x3
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x4
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x5
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x6
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_0 := calldataload(0x0624)
                    let a_1 := calldataload(0x0644)
                    let var19 := sub(r, a_1)
                    let var20 := addmod(a_0, var19, r)
                    let var21 := sub(r, var20)
                    let var22 := addmod(a_2, var21, r)
                    let var23 := mulmod(var18, var22, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var23, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x3
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x5
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x6
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_1 := calldataload(0x0644)
                    let a_2_prev_1 := calldataload(0x0764)
                    let var19 := addmod(a_1, a_2_prev_1, r)
                    let var20 := sub(r, var19)
                    let var21 := addmod(a_2, var20, r)
                    let var22 := mulmod(var18, var21, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var22, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x3
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x4
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x6
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x7
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_2 := calldataload(0x0664)
                    let a_1 := calldataload(0x0644)
                    let var19 := sub(r, a_1)
                    let var20 := sub(r, var19)
                    let var21 := addmod(a_2, var20, r)
                    let var22 := mulmod(var18, var21, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var22, r)
                }
                {
                    let f_13 := calldataload(0x0924)
                    let var0 := 0x1
                    let var1 := sub(r, f_13)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_13, var2, r)
                    let var4 := 0x2
                    let var5 := addmod(var4, var1, r)
                    let var6 := mulmod(var3, var5, r)
                    let var7 := 0x3
                    let var8 := addmod(var7, var1, r)
                    let var9 := mulmod(var6, var8, r)
                    let var10 := 0x4
                    let var11 := addmod(var10, var1, r)
                    let var12 := mulmod(var9, var11, r)
                    let var13 := 0x5
                    let var14 := addmod(var13, var1, r)
                    let var15 := mulmod(var12, var14, r)
                    let var16 := 0x6
                    let var17 := addmod(var16, var1, r)
                    let var18 := mulmod(var15, var17, r)
                    let a_1 := calldataload(0x0644)
                    let var19 := mulmod(var18, a_1, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var19, r)
                }
                {
                    let f_14 := calldataload(0x0944)
                    let var0 := 0x1
                    let var1 := sub(r, f_14)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_14, var2, r)
                    let a_1 := calldataload(0x0644)
                    let var4 := sub(r, var0)
                    let var5 := addmod(a_1, var4, r)
                    let var6 := mulmod(a_1, var5, r)
                    let var7 := mulmod(var3, var6, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var7, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, sub(r, mulmod(l_0, calldataload(0x0aa4), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let perm_z_last := calldataload(0x0b04)
                    let eval := mulmod(mload(L_LAST_MPTR), addmod(mulmod(perm_z_last, perm_z_last, r), sub(r, perm_z_last), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0b04), sub(r, calldataload(0x0ae4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let gamma := mload(GAMMA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let lhs := calldataload(0x0ac4)
                    let rhs := calldataload(0x0aa4)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0624), mulmod(beta, calldataload(0x0984), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0644), mulmod(beta, calldataload(0x09a4), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0664), mulmod(beta, calldataload(0x09c4), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0784), mulmod(beta, calldataload(0x09e4), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0684), mulmod(beta, calldataload(0x0a04), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x06a4), mulmod(beta, calldataload(0x0a24), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x07a4), mulmod(beta, calldataload(0x0a44), r), r), gamma, r), r)
                    mstore(0x00, mulmod(beta, mload(X_MPTR), r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0624), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0644), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0664), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0784), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0684), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x06a4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x07a4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    let left_sub_right := addmod(lhs, sub(r, rhs), r)
                    let eval := addmod(left_sub_right, sub(r, mulmod(left_sub_right, addmod(mload(L_LAST_MPTR), mload(L_BLIND_MPTR), r), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let gamma := mload(GAMMA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let lhs := calldataload(0x0b24)
                    let rhs := calldataload(0x0b04)
                    lhs := mulmod(lhs, addmod(addmod(mload(INSTANCE_EVAL_MPTR), mulmod(beta, calldataload(0x0a64), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x07c4), mulmod(beta, calldataload(0x0a84), r), r), gamma, r), r)
                    rhs := mulmod(rhs, addmod(addmod(mload(INSTANCE_EVAL_MPTR), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x07c4), mload(0x00), r), gamma, r), r)
                    let left_sub_right := addmod(lhs, sub(r, rhs), r)
                    let eval := addmod(left_sub_right, sub(r, mulmod(left_sub_right, addmod(mload(L_LAST_MPTR), mload(L_BLIND_MPTR), r), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := mulmod(l_0, calldataload(0x0b44), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, calldataload(0x0b44), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let table
                    {
                        let f_5 := calldataload(0x0824)
                        let f_6 := calldataload(0x0844)
                        table := f_5
                        table := addmod(mulmod(table, theta, r), f_6, r)
                        table := addmod(table, beta, r)
                    }
                    let input_0
                    {
                        let f_9 := calldataload(0x08a4)
                        let var0 := 0x1
                        let var1 := mulmod(f_9, var0, r)
                        let a_0 := calldataload(0x0624)
                        let var2 := mulmod(var1, a_0, r)
                        let var3 := sub(r, var1)
                        let var4 := addmod(var0, var3, r)
                        let var5 := 0x0
                        let var6 := mulmod(var4, var5, r)
                        let var7 := addmod(var2, var6, r)
                        let a_1 := calldataload(0x0644)
                        let var8 := mulmod(var1, a_1, r)
                        let var9 := addmod(var8, var6, r)
                        input_0 := var7
                        input_0 := addmod(mulmod(input_0, theta, r), var9, r)
                        input_0 := addmod(input_0, beta, r)
                    }
                    let lhs
                    let rhs
                    rhs := table
                    {
                        let tmp := input_0
                        rhs := addmod(rhs, sub(r, mulmod(calldataload(0x0b84), tmp, r)), r)
                        lhs := mulmod(mulmod(table, tmp, r), addmod(calldataload(0x0b64), sub(r, calldataload(0x0b44)), r), r)
                    }
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := mulmod(l_0, calldataload(0x0ba4), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, calldataload(0x0ba4), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let table
                    {
                        let f_5 := calldataload(0x0824)
                        let f_7 := calldataload(0x0864)
                        table := f_5
                        table := addmod(mulmod(table, theta, r), f_7, r)
                        table := addmod(table, beta, r)
                    }
                    let input_0
                    {
                        let f_10 := calldataload(0x08c4)
                        let var0 := 0x1
                        let var1 := mulmod(f_10, var0, r)
                        let a_0 := calldataload(0x0624)
                        let var2 := mulmod(var1, a_0, r)
                        let var3 := sub(r, var1)
                        let var4 := addmod(var0, var3, r)
                        let var5 := 0x0
                        let var6 := mulmod(var4, var5, r)
                        let var7 := addmod(var2, var6, r)
                        let a_1 := calldataload(0x0644)
                        let var8 := mulmod(var1, a_1, r)
                        let var9 := addmod(var8, var6, r)
                        input_0 := var7
                        input_0 := addmod(mulmod(input_0, theta, r), var9, r)
                        input_0 := addmod(input_0, beta, r)
                    }
                    let lhs
                    let rhs
                    rhs := table
                    {
                        let tmp := input_0
                        rhs := addmod(rhs, sub(r, mulmod(calldataload(0x0be4), tmp, r)), r)
                        lhs := mulmod(mulmod(table, tmp, r), addmod(calldataload(0x0bc4), sub(r, calldataload(0x0ba4)), r), r)
                    }
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := mulmod(l_0, calldataload(0x0c04), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, calldataload(0x0c04), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let table
                    {
                        let f_5 := calldataload(0x0824)
                        let f_8 := calldataload(0x0884)
                        table := f_5
                        table := addmod(mulmod(table, theta, r), f_8, r)
                        table := addmod(table, beta, r)
                    }
                    let input_0
                    {
                        let f_11 := calldataload(0x08e4)
                        let var0 := 0x1
                        let var1 := mulmod(f_11, var0, r)
                        let a_0 := calldataload(0x0624)
                        let var2 := mulmod(var1, a_0, r)
                        let var3 := sub(r, var1)
                        let var4 := addmod(var0, var3, r)
                        let var5 := 0x0
                        let var6 := mulmod(var4, var5, r)
                        let var7 := addmod(var2, var6, r)
                        let a_1 := calldataload(0x0644)
                        let var8 := mulmod(var1, a_1, r)
                        let var9 := mulmod(var4, var0, r)
                        let var10 := addmod(var8, var9, r)
                        input_0 := var7
                        input_0 := addmod(mulmod(input_0, theta, r), var10, r)
                        input_0 := addmod(input_0, beta, r)
                    }
                    let lhs
                    let rhs
                    rhs := table
                    {
                        let tmp := input_0
                        rhs := addmod(rhs, sub(r, mulmod(calldataload(0x0c44), tmp, r)), r)
                        lhs := mulmod(mulmod(table, tmp, r), addmod(calldataload(0x0c24), sub(r, calldataload(0x0c04)), r), r)
                    }
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }

                pop(y)
                pop(delta)

                let quotient_eval := mulmod(quotient_eval_numer, mload(X_N_MINUS_1_INV_MPTR), r)
                mstore(QUOTIENT_EVAL_MPTR, quotient_eval)
            }

            // Compute quotient commitment
            {
                mstore(0x00, calldataload(LAST_QUOTIENT_X_CPTR))
                mstore(0x20, calldataload(add(LAST_QUOTIENT_X_CPTR, 0x20)))
                let x_n := mload(X_N_MPTR)
                for
                    {
                        let cptr := sub(LAST_QUOTIENT_X_CPTR, 0x40)
                        let cptr_end := sub(FIRST_QUOTIENT_X_CPTR, 0x40)
                    }
                    lt(cptr_end, cptr)
                    {}
                {
                    success := ec_mul_acc(success, x_n)
                    success := ec_add_acc(success, calldataload(cptr), calldataload(add(cptr, 0x20)))
                    cptr := sub(cptr, 0x40)
                }
                mstore(QUOTIENT_X_MPTR, mload(0x00))
                mstore(QUOTIENT_Y_MPTR, mload(0x20))
            }

            // Compute pairing lhs and rhs
            {
                {
                    let x := mload(X_MPTR)
                    let omega := mload(OMEGA_MPTR)
                    let omega_inv := mload(OMEGA_INV_MPTR)
                    let x_pow_of_omega := mulmod(x, omega, r)
                    mstore(0x0420, x_pow_of_omega)
                    mstore(0x0400, x)
                    x_pow_of_omega := mulmod(x, omega_inv, r)
                    mstore(0x03e0, x_pow_of_omega)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    mstore(0x03c0, x_pow_of_omega)
                }
                {
                    let mu := mload(MU_MPTR)
                    for
                        {
                            let mptr := 0x0440
                            let mptr_end := 0x04c0
                            let point_mptr := 0x03c0
                        }
                        lt(mptr, mptr_end)
                        {
                            mptr := add(mptr, 0x20)
                            point_mptr := add(point_mptr, 0x20)
                        }
                    {
                        mstore(mptr, addmod(mu, sub(r, mload(point_mptr)), r))
                    }
                    let s
                    s := mload(0x0480)
                    mstore(0x04c0, s)
                    let diff
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x0460), r)
                    diff := mulmod(diff, mload(0x04a0), r)
                    mstore(0x04e0, diff)
                    mstore(0x00, diff)
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x04a0), r)
                    mstore(0x0500, diff)
                    diff := mload(0x0440)
                    mstore(0x0520, diff)
                    diff := mload(0x0460)
                    mstore(0x0540, diff)
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x0460), r)
                    mstore(0x0560, diff)
                }
                {
                    let point_2 := mload(0x0400)
                    let coeff
                    coeff := 1
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x20, coeff)
                }
                {
                    let point_1 := mload(0x03e0)
                    let point_2 := mload(0x0400)
                    let coeff
                    coeff := addmod(point_1, sub(r, point_2), r)
                    coeff := mulmod(coeff, mload(0x0460), r)
                    mstore(0x40, coeff)
                    coeff := addmod(point_2, sub(r, point_1), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x60, coeff)
                }
                {
                    let point_1 := mload(0x03e0)
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_1, sub(r, point_2), r)
                    coeff := mulmod(coeff, addmod(point_1, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0460), r)
                    mstore(0x80, coeff)
                    coeff := addmod(point_2, sub(r, point_1), r)
                    coeff := mulmod(coeff, addmod(point_2, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0xa0, coeff)
                    coeff := addmod(point_3, sub(r, point_1), r)
                    coeff := mulmod(coeff, addmod(point_3, sub(r, point_2), r), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0xc0, coeff)
                }
                {
                    let point_0 := mload(0x03c0)
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_0, sub(r, point_2), r)
                    coeff := mulmod(coeff, addmod(point_0, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0440), r)
                    mstore(0xe0, coeff)
                    coeff := addmod(point_2, sub(r, point_0), r)
                    coeff := mulmod(coeff, addmod(point_2, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x0100, coeff)
                    coeff := addmod(point_3, sub(r, point_0), r)
                    coeff := mulmod(coeff, addmod(point_3, sub(r, point_2), r), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0x0120, coeff)
                }
                {
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_2, sub(r, point_3), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x0140, coeff)
                    coeff := addmod(point_3, sub(r, point_2), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0x0160, coeff)
                }
                {
                    success := batch_invert(success, 0, 0x0180, r)
                    let diff_0_inv := mload(0x00)
                    mstore(0x04e0, diff_0_inv)
                    for
                        {
                            let mptr := 0x0500
                            let mptr_end := 0x0580
                        }
                        lt(mptr, mptr_end)
                        { mptr := add(mptr, 0x20) }
                    {
                        mstore(mptr, mulmod(mload(mptr), diff_0_inv, r))
                    }
                }
                {
                    let coeff := mload(0x20)
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0964), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, mload(QUOTIENT_EVAL_MPTR), r), r)
                    for
                        {
                            let mptr := 0x0a84
                            let mptr_end := 0x0964
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x20) }
                    {
                        r_eval := addmod(mulmod(r_eval, zeta, r), mulmod(coeff, calldataload(mptr), r), r)
                    }
                    for
                        {
                            let mptr := 0x0944
                            let mptr_end := 0x0764
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x20) }
                    {
                        r_eval := addmod(mulmod(r_eval, zeta, r), mulmod(coeff, calldataload(mptr), r), r)
                    }
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0c44), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0be4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0b84), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0704), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0644), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0624), r), r)
                    mstore(0x0580, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0x40), calldataload(0x0764), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x60), calldataload(0x0664), r), r)
                    r_eval := mulmod(r_eval, mload(0x0500), r)
                    mstore(0x05a0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0x80), calldataload(0x0724), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x06a4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x06e4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x80), calldataload(0x0744), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0684), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x06c4), r), r)
                    r_eval := mulmod(r_eval, mload(0x0520), r)
                    mstore(0x05c0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0xe0), calldataload(0x0ae4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0100), calldataload(0x0aa4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0120), calldataload(0x0ac4), r), r)
                    r_eval := mulmod(r_eval, mload(0x0540), r)
                    mstore(0x05e0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0c04), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0c24), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0ba4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0bc4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0b44), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0b64), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0b04), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0b24), r), r)
                    r_eval := mulmod(r_eval, mload(0x0560), r)
                    mstore(0x0600, r_eval)
                }
                {
                    let sum := mload(0x20)
                    mstore(0x0620, sum)
                }
                {
                    let sum := mload(0x40)
                    sum := addmod(sum, mload(0x60), r)
                    mstore(0x0640, sum)
                }
                {
                    let sum := mload(0x80)
                    sum := addmod(sum, mload(0xa0), r)
                    sum := addmod(sum, mload(0xc0), r)
                    mstore(0x0660, sum)
                }
                {
                    let sum := mload(0xe0)
                    sum := addmod(sum, mload(0x0100), r)
                    sum := addmod(sum, mload(0x0120), r)
                    mstore(0x0680, sum)
                }
                {
                    let sum := mload(0x0140)
                    sum := addmod(sum, mload(0x0160), r)
                    mstore(0x06a0, sum)
                }
                {
                    for
                        {
                            let mptr := 0x00
                            let mptr_end := 0xa0
                            let sum_mptr := 0x0620
                        }
                        lt(mptr, mptr_end)
                        {
                            mptr := add(mptr, 0x20)
                            sum_mptr := add(sum_mptr, 0x20)
                        }
                    {
                        mstore(mptr, mload(sum_mptr))
                    }
                    success := batch_invert(success, 0, 0xa0, r)
                    let r_eval := mulmod(mload(0x80), mload(0x0600), r)
                    for
                        {
                            let sum_inv_mptr := 0x60
                            let sum_inv_mptr_end := 0xa0
                            let r_eval_mptr := 0x05e0
                        }
                        lt(sum_inv_mptr, sum_inv_mptr_end)
                        {
                            sum_inv_mptr := sub(sum_inv_mptr, 0x20)
                            r_eval_mptr := sub(r_eval_mptr, 0x20)
                        }
                    {
                        r_eval := mulmod(r_eval, mload(NU_MPTR), r)
                        r_eval := addmod(r_eval, mulmod(mload(sum_inv_mptr), mload(r_eval_mptr), r), r)
                    }
                    mstore(R_EVAL_MPTR, r_eval)
                }
                {
                    let nu := mload(NU_MPTR)
                    mstore(0x00, calldataload(0x03e4))
                    mstore(0x20, calldataload(0x0404))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(QUOTIENT_X_MPTR), mload(QUOTIENT_Y_MPTR))
                    for
                        {
                            let mptr := 0x0f20
                            let mptr_end := 0x0a60
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_acc(success, mload(ZETA_MPTR))
                        success := ec_add_acc(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(0x09e0), mload(0x0a00))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(0x09a0), mload(0x09c0))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(0x0a60), mload(0x0a80))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(0x0a20), mload(0x0a40))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, mload(0x0960), mload(0x0980))
                    for
                        {
                            let mptr := 0x0264
                            let mptr_end := 0x0164
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_acc(success, mload(ZETA_MPTR))
                        success := ec_add_acc(success, calldataload(mptr), calldataload(add(mptr, 0x20)))
                    }
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, calldataload(0xa4), calldataload(0xc4))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, calldataload(0x64), calldataload(0x84))
                    mstore(0x80, calldataload(0xe4))
                    mstore(0xa0, calldataload(0x0104))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0500), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x0164))
                    mstore(0xa0, calldataload(0x0184))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0124), calldataload(0x0144))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0520), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x02a4))
                    mstore(0xa0, calldataload(0x02c4))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0540), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x03a4))
                    mstore(0xa0, calldataload(0x03c4))
                    for
                        {
                            let mptr := 0x0364
                            let mptr_end := 0x02a4
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, calldataload(mptr), calldataload(add(mptr, 0x20)))
                    }
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0560), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, mload(G1_X_MPTR))
                    mstore(0xa0, mload(G1_Y_MPTR))
                    success := ec_mul_tmp(success, sub(r, mload(R_EVAL_MPTR)))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, calldataload(0x0c64))
                    mstore(0xa0, calldataload(0x0c84))
                    success := ec_mul_tmp(success, sub(r, mload(0x04c0)))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, calldataload(0x0ca4))
                    mstore(0xa0, calldataload(0x0cc4))
                    success := ec_mul_tmp(success, mload(MU_MPTR))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(PAIRING_LHS_X_MPTR, mload(0x00))
                    mstore(PAIRING_LHS_Y_MPTR, mload(0x20))
                    mstore(PAIRING_RHS_X_MPTR, calldataload(0x0ca4))
                    mstore(PAIRING_RHS_Y_MPTR, calldataload(0x0cc4))
                }
            }

            // Random linear combine with accumulator
            if mload(HAS_ACCUMULATOR_MPTR) {
                mstore(0x00, mload(ACC_LHS_X_MPTR))
                mstore(0x20, mload(ACC_LHS_Y_MPTR))
                mstore(0x40, mload(ACC_RHS_X_MPTR))
                mstore(0x60, mload(ACC_RHS_Y_MPTR))
                mstore(0x80, mload(PAIRING_LHS_X_MPTR))
                mstore(0xa0, mload(PAIRING_LHS_Y_MPTR))
                mstore(0xc0, mload(PAIRING_RHS_X_MPTR))
                mstore(0xe0, mload(PAIRING_RHS_Y_MPTR))
                let challenge := mod(keccak256(0x00, 0x100), r)

                // [pairing_lhs] += challenge * [acc_lhs]
                success := ec_mul_acc(success, challenge)
                success := ec_add_acc(success, mload(PAIRING_LHS_X_MPTR), mload(PAIRING_LHS_Y_MPTR))
                mstore(PAIRING_LHS_X_MPTR, mload(0x00))
                mstore(PAIRING_LHS_Y_MPTR, mload(0x20))

                // [pairing_rhs] += challenge * [acc_rhs]
                mstore(0x00, mload(ACC_RHS_X_MPTR))
                mstore(0x20, mload(ACC_RHS_Y_MPTR))
                success := ec_mul_acc(success, challenge)
                success := ec_add_acc(success, mload(PAIRING_RHS_X_MPTR), mload(PAIRING_RHS_Y_MPTR))
                mstore(PAIRING_RHS_X_MPTR, mload(0x00))
                mstore(PAIRING_RHS_Y_MPTR, mload(0x20))
            }

            // Perform pairing
            success := ec_pairing(
                success,
                mload(PAIRING_LHS_X_MPTR),
                mload(PAIRING_LHS_Y_MPTR),
                mload(PAIRING_RHS_X_MPTR),
                mload(PAIRING_RHS_Y_MPTR)
            )

            // Revert if anything fails
            if iszero(success) {
                revert(0x00, 0x00)
            }

            // Return 1 as result if everything succeeds
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }
}
