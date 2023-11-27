// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {LibStruct} from "./lib/LibStruct.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {BalanceScale} from "./ezkl/BalanceScale.sol";
import {DataAttestation} from "./ezkl/DataAttestor.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title BalanceScaleTest
/// @notice Tests BalanceScale E2E demo implementation
contract BalanceScaleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice EZKL Data Attestor
    DataAttestation internal ATTESTOR;

    /// @notice BalanceScale demo implementation
    BalanceScale internal BALANCE_SCALE;

    /// @notice Infernet coordinator
    EIP712Coordinator internal COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Setup coordinator
        COORDINATOR = new EIP712Coordinator();

        // Pre-predict expected address of contract(BALANCE_SCALE)
        address balanceScaleAddr = 0x0F8458E544c9D4C7C25A881240727209caae20B8;

        // Setup input parameters for attestor contract
        // Contract address to staticcall (our consumer contract, in this case, address(BalanceScale))
        address[] memory _contractAddresses = new address[](1);
        _contractAddresses[0] = balanceScaleAddr;

        // Function calldata to get int256[4] input parameters
        bytes[][] memory _calldata = new bytes[][](1);
        _calldata[0] = new bytes[](4);
        // We expose the current int256[4] parameters via BalanceScale.currentData
        // We can simply encode the getter function for this public int256[4] state
        bytes4 GETTER_SELECTOR = bytes4(keccak256("currentData(uint256)"));
        for (uint8 i = 0; i < 4; i++) {
            _calldata[0][i] = abi.encodeWithSelector(GETTER_SELECTOR, i);
        }

        // Decimals and scaling are default set to 0 for balance scale model
        uint256[][] memory _decimals = new uint256[][](1);
        _decimals[0] = new uint256[](4);
        uint256[] memory _scales = new uint256[](4);
        for (uint8 i = 0; i < 4; i++) {
            _decimals[0][i] = 0;
            _scales[i] = 0;
        }

        // Initialize new attestor contract with BalanceScale view-only fn parameters
        ATTESTOR = new DataAttestation(
            _contractAddresses,
            _calldata,
            _decimals,
            _scales,
            0,
            address(this)
        );

        // Deploy verifier contract
        // Uses compiled artifacts directly from ~ROOT/out
        address VERIFIER = deployCode("Verifier.sol:Halo2Verifier");

        // Setup mock node (ALICE) and move to NodeStatus.Active
        ALICE = new MockNode(COORDINATOR);
        vm.warp(0);
        ALICE.registerNode(address(ALICE));
        vm.warp(COORDINATOR.cooldown());
        ALICE.activateNode();

        // Setup balance scale contract
        BALANCE_SCALE = new BalanceScale(
            address(COORDINATOR),
            address(ATTESTOR),
            VERIFIER
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test E2E flow (push inputs, initiate callback, get response, verify response)
    function testE2E() public {
        // Setup expected output and inputs
        int256 expectedOutput = 0; // expected result is leaning left (0)
        int256[4] memory inputs = [int256(1), int256(5), int256(2), int256(2)]; // inputs: [1, 5, 2, 2]

        // Setup proof (exact input to Verifier.verifyProof, including 4-byte signature)
        bytes memory proof =
            hex"1e8e1e130000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000096000000000000000000000000000000000000000000000000000000000000009001f2610322a656f2656716edade9f8f4f65e4ebc1acae6f01be747f65b4e7f7a01649425d0c2abea53bbe1ec30b35af753b23b008ee661506b049110fd37bdd6a2b72ada35b140c3a4a459136f8c7e9440bbb95f66636f8c8068e5d3204e92a3c1ba834aecef82f384bea9317998da017f873d95d86c587a8145a21fe900fdb47255c6109c47ad31d3e6fa005bb54887b96e2feddef6805d40089837b3a91f30d258973fa0400d78cab5bc5e2dea6618a260649283619528eaab0f76f609fc8921108cb7dc0de917ab888eb426f4d3390c9cc249f702a8dafafc6c4bdc096a92903265c413fcf6a16e4fa572c75cf8a0398615079c182c2f86ae2f4a2f6f9b40a14fd7af74b979352bf2d74d88b29f7acc78327f0b0ffc1d08147e0cb88a3ca5f2015b4c1792d908f88a2aa1095e4cb0cd95764834ea436f4e8edc45f4eb23779223773d267883beb51938377ed54f8769a83b3fdea2fb5f4544a4b26165d9b8408585beb85090fd77eb5a86de419367655bdc4358cfe1fe37ef92554eda54d9721c6b913a437e4fd2e90cb69f8f7ce9f4afbc6f974522ce9469798c4b91954871927041e25129e7024ff11836e08cac0a1ca0a628652841d12e787fe700b9ac5118213d37ce7335749108c92a0be54d80c7639a6b8565a6dc4c4908bb121c8bf29e7a431b23a833ff089cd27e9ddbbf6fe9ddb48fa22bdd54e700d9a97e31b721608654651340c32ef9bd3d42ba9051963ebce7ccbba8d1e452e57310e61c1f72e2d6777d4fc8ed7d59c32a5d4b52fe2820f7b0702d79d9a865294df6fc9020c22bdbefbfdd1e6264f163d86eab4305189644e6376dd590076eabb45bfae3a8a2f20cce3a95649073fe9106f12054ac83d694b817bcf6b571bed811f9f3c176021a56af12dd22cb147248d2130902b30bd6ef4c372519e1515996ab52e7f4d742363245ca3c7b5ba6d644131396a46174c1c77ea8757200349ca2763bd5689d42e132b6e5d2d7a548ac5d9d1d72b336684c40313b9fbd124b7596044cdb4d95e1dd99ba10afe0af4ac06a42ad4682ef4808d3319f2dee0bfc6aa5d43a8760d6b09a05745f5988c0ab42042d1f3b527abd61a0f46b73a10b6b19f4699e2f27b692b1448837a0de08eaf751a697524e5d4aa8ab34daf7b34665012ec02a4d29d4911368252e8091b10750117520515007e5eaa796499923ab4122fd093d3e2e92a2313fd6f0ded0749085c1ae71b6349232d09cbaf1c3f1d0b5b46ef38159e361a0e9bc48ceb8eb0b8ec1fa17d01e020279fb9ffcdfdadedd9a07f692871c1c3352495d2009c0e61fa2b264c9cb391860b949be3fdd096a3dc8cfe7e65a42454f31a4870c10dc76151cdcedfb04de0dc651e17f85c4995a84cb40a157ae4f6ea6d03ff483d07e8989e2a204d012a7d6b29f27ed6e7afb4b9fb3cf1b6efe8a0f6c729d591471410dbbffd312f18c26ea69d303f638ebca0393541e11622aa7c6a7606405961e062db1f56cb67829545062e1cdcff30fc9d6ba82be3b902fdc859bf16178d28fae2d800a2efc57ac0fa43784cd0dbaebb966e7fc7a898ea29d5f53d296caaa93c14285487c3000ac3512219243e0b6b391a68fdf2be8fe49d31436a1d3b314411d67128247b07c3fe7c09f1a9b24613cc346ec6df4956ea5972e9562d1ff4c476f32968532c56e16e62840456ade318d83bc3f3f08b30c7bb03b10e2d24b9b96dca54b65daf30752c803998376c4764321894b978d8960b8ceb0ce72158e0990df795372af50760aafc018e18e63483ba374abcc77b95c6745d9bb80df101d75b532ecc53cf11c477c3c6cd2396d710b5c85f9af5fc56b6e5dc2c74116f52769fe2fb7e71bd06d513681559c3477e04af04ec154fdc9c2f531d1ef526c9bd50f6d5ee0d46e361df36cd1958da82c4b4eaa002c2407448756ca3034a0987277516017519136d26f818ec037d1cbc98628f272bd6c86ceff6c41555311619a3996a90fec46c8193ebb8f72069bc5622f485db92656a7a0ba42c38000d07e21cc1ccb908cc8d6f8c7733ab61bf1641b2491ccfbf1c8d69bc8d971dd9ae23efc6f0cbf35bca881ecd70d99c76e87e775a48b318e2058d273df85b23e1662209d27eaed432e0f4721b2666fd710e6ee61b8d97a63872e0843732928e8c8e12caf63cf44d91066b28799335cd0ebf2261e8a9546afbd1abb77ae4f40470a322dd021a4c0e7ca8c968d4e9fa1a2b66cd7de5dfa220031ec88d10abc9e33a0828dd0e5f4865c9fc258f181bd9b7c572d33b4d0adc7fac1a7674b94f5f9edf35029f7e2c1c0e35f58c7efc28cc072c0bc3800db27c792e2da013d772fedab6181717b6127405d01b6dc91f473e8aaab0c17fdc4f9f02ece0e1a00c16e1a842ac1a5e0a50f4e9b24456f925dda8d28b1e90dbc825bd37959b17be81f91446792102dfea37e699ff576b865a45bd4d9573161c9594014f5566621105230ba095b904ea38680c1af826606c8c351173281f6be0cbe1bd19eea33f9edfe60a77d1c005a7758de6c2d60c233150d31172825ea5a92ed16a3c567ad40cdfabb5fdf35200ef455659e7d7d4dd2fc6ef6914480fd5880d8d0f76fe80bedaaf17516778ec2004f4831981fd6ec691632458e73860a63f602fd88bf540cc1c4b179089524507a5206b381860bcfef981d3faf3939c174f57a45033e567d56fc020471e469120e4a077270529eb7b9ace015a63e490737c741c9ba72ce0b186b91664ffdb7027db7b61f1c8e76b2f0e12b8381bcf8e212f6a411a59d0bf2cd4fc4fdf35879719c6e89f934cc972f9757f4fe0f2b6450cc7018f9251e92dcca7d0e7b5c46bff1f8fe10d734acb08c1f18c59e8eb9448bb68ea491ab2241ebf3b8c3d6ef4cfde0345ea688fb853f413570297e22eb5232ecbcb60106f3ec4b000276f07588029194575b54130cfed69fed5ce22227e94b388f38919c1a1ee00dc57749c7cea501fcfc2b838d05b1463a63e088dcef8814b1e4f687ea758d416f0e8a268e04b8d2ca956ee12faf56f1fd85af6e1f446468345749851d1024d7cab2e470f188e4305ee66c64d8ed6ef0e58a74f489b1cf01338796b4df1993bcbfd7f775649c01327ef48e58a3d98c9c0b2cf4166a4ede32ac86f2ad03dd647a1749449557a3ac01a483be7099a828fd980dd365189ef9b3509125249c423e8518eb9312d934eec177ae067117ead24cf2e888940559b2531db4bf4d9fe3175e1ab007c9167a0f400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Initiate prediction w/ inputs
        BALANCE_SCALE.initiatePrediction(inputs);

        // Get new subscription
        uint32 subscriptionId = 1;
        LibStruct.Subscription memory sub = LibStruct.getSubscription(COORDINATOR, subscriptionId);

        (int256[4] memory features) = abi.decode(sub.inputs, (int256[4]));
        for (uint8 i = 0; i < 4; i++) {
            // Assert features are correctly stored
            assertEq(inputs[i], features[i]);
            // Assert inputs are correctly stored
            assertEq(inputs[i], BALANCE_SCALE.data(subscriptionId, i));
        }

        // Hash recorded container input + prepare for delivery
        bytes32 hashedInput = keccak256(abi.encode(inputs));
        bytes memory input = abi.encode(hashedInput);

        // Submit compute container response from Alice w/ correct proof
        ALICE.deliverCompute(subscriptionId, 1, input, "really,any,response,here,we,read,true,output,from,proof", proof);

        // Assert actual output conforms to expected output
        int256 actualOutput = BALANCE_SCALE.predictions(subscriptionId);
        assertEq(actualOutput, expectedOutput);
    }
}
