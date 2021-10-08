pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MasterDemon is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;

    struct UserInfo {
        uint256 tokenId;
        address contractAddress;
    }

    struct Collection {
        // some dummy values
        uint256 stakingFee;
        uint256 harvestingFee;
        uint256 withdrawingFee;
        uint256 normalizer;
        uint256 multiplier;
        bool isStakable;
    }

    /// @notice address => each user
    mapping(address => UserInfo[]) public userInfo;

    /// @notice array of each nft collection
    mapping(address => Collection) public collections;

    /// @notice LLTH token
    IERC20 public llth;

    event UserStaked(address staker);
    event UserUnstaked(address unstaker);
    event UserHarvested(address harvester);

    constructor(IERC20 _llth) public {
        llth = _llth;
    }

    // ------------------------ PUBLIC/EXTERNAL ------------------------ //

    function stake(uint256 _cid, uint256 _id) external {
        _stake(msg.sender, _cid, _id);
    }

    function unstake(uint256 _id, uint256 _cid) external {
        _unstake(msg.sender, _cid, _id);
    }

    function stakeBatch(uint256 _cid, uint256[] memory _ids) external {
        for (uint256 i = 0; i < _ids.length; ++i) {
            _stake(msg.sender, _cid, _ids[i]);
        }
    }

    function unstakeBatch(uint256[] memory _ids, uint256 _cid) external {
        for (uint256 i = 0; i < _ids.length; ++i) {
            _unstake(msg.sender, _cid, _ids[i]);
        }
    }

    function harvest() external {
        _harvest(msg.sender);
    }

    // ------------------------ INTERNAL ------------------------ //

    /// @notice stake single nft (called in external function)
    /// @param _user = msg.sender
    /// @param _nft = collection address
    /// @param _id = nft id
    function _stake(
        address _user,
        address _nft,
        uint256 _id
    ) internal {
        Collection memory collection = collections[_nft];
        UserInfo memory user;
        require(
            IERC721(collection.contractAddress).ownerOf(_id) ==
                address(_user),
            "ERR: YOU DONT OWN THIS TOKEN"
        );
        IERC721(collection.contractAddress).safeTransferFrom(
            _user,
            address(this),
            _id
        );
        user.amountStaked = user.amountStaked.add(1);
        user.tokenIds.push(_id);
        user.tokenIdsMapping[_id] == true;

        emit UserStaked(_user);

        userInfo[_user].push(user);
    }

    /// @notice unstake single nft (called in external function)
    /// @param _user = msg.sender
    /// @param _nft = collection address
    /// @param _id = nft id
    function _unstake(
        address _user,
        address _nft,
        uint256 _id
    ) internal {
        Collection memory collection = collections[_nft];
        UserInfo storage user = userInfo[_user];
        require(
            user.tokenIdsMapping[_id] == true,
            "YOU DONT OWN THE TOKEN AT GIVEN INDEX"
        );
        IERC721(collection.contractAddress).safeTransferFrom(
            address(this),
            _user,
            _id
        );

        uint256 lastIndex = user.tokenIds.length - 1;
        uint256 lastIndexKey = user.tokenIds[lastIndex];
        uint256 tokenIdIndex = user.tokenIndex[_id];

        user.tokenIds[tokenIdIndex] = lastIndexKey;
        user.tokenIndex[lastIndexKey] = tokenIdIndex;
        if (user.tokenIds.length > 0) {
            user.tokenIds.pop();
            user.tokenIdsMapping[_id] == false;
            delete user.tokenIndex[_id];
            user.amountStaked -= 1;
        }

        if (user.amountStaked == 0) {
            delete userInfo[msg.sender];
        }

        emit UserUnstaked(_user);
    }

    function _harvest(address _user) internal {
        uint256 rarity = _getRarity(); // will take NFT ID
        uint256 APY = 1; // notice its dummy variable
        llth.transfer(_user, APY);
        UserInfo storage user = userInfo[_user];
        user.currentRewad = user.currentRewad.sub(APY);

        emit UserHarvested(_user);
    }

    /// @notice dummy function, will be replaced by oracle later
    function _getRarity() internal pure returns (uint256) {
        return 40;
    }

    /// @notice will calculate rarity based on our formula
    /// @param _rarity number given my trait normalization formula
    /// @param _normalizer number that will range _rarity into normalized numbers range
    /// @param _daysStaked maturity period
    /// @param _multiplier pool can have multiplier
    /// @param _amountOfStakers used to minimize rewards proportionally to pool popularity
    function _calculateRewards(
        uint256 _rarity,
        uint256 _normalizer,
        uint256 _daysStaked,
        uint256 _multiplier,
        uint256 _amountOfStakers
    ) internal returns (uint256) {
        require(
            _rarity != 0 &&
            _daysStaked != 0 &&
            _multiplier != 0 &&
            _amountOfStakers != 0 &&
            _normalizer != 0,
            "CANT BE ZERO"
        );

        uint256 baseMultiplier = _multiplier.mul(_daysStaked);
        uint256 baseRarity = _normalizer.mul(_rarity);
        uint256 basemultiplierxRarity = baseMultiplier.mul(baseRarity);
        uint256 finalReward = basemultiplierxRarity.div(_amountOfStakers);

        return finalReward;
    }

    // ------------------------ ADMIN ------------------------ //

    function setCollection(
        bool _isStakable,
        address _contractAddress,
        uint256 _stakingFee,
        uint256 _harvestingFee,
        uint256 _withdrawingFee,
        uint256 _normalizer,
        uint256 _multiplier
    ) public onlyOwner {
        collections[_contractAddress] = Collection({
            stakingFee: _stakingFee,
            harvestingFee: _harvestingFee,
            withdrawingFee: _withdrawingFee,
            normalizer: _normalizer,
            multiplier: _multiplier,
            isStakable: _isStakable,
        });
    }

    function updateCollection(
        uint256 _cid,
        bool _isStakable,
        address _contractAddress,
        uint256 _stakingFee,
        uint256 _harvestingFee,
        uint256 _withdrawingFee,
        uint256 _normalizer,
        uint256 _multiplier
    ) public onlyOwner {
        Collection memory collection = collections[_cid];
        collection.isStakable = _isStakable;
        collection.contractAddress = _contractAddress;
        collection.stakingFee = _stakingFee;
        collection.harvestingFee = _harvestingFee;
        collection.withdrawingFee = _withdrawingFee;
        collection.normalizer = _normalizer;
        collection.multiplier = _multiplier;
    }

    function manageCollection(uint256 _cid, bool _isStakable) public onlyOwner {
        Collection memory collection = collections[_cid];
        collection.isStakable = _isStakable;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
