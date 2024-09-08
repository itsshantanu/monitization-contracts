// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/onft-evm/contracts/onft721/ONFT721.sol";

contract OmnichainMonetization is Ownable, ReentrancyGuard, ONFT721 {
    uint256 private _tokenIdCounter;

    struct Content {
        address payable creator;
        string contentHash;
        uint256 price;
        uint256 royaltyPercentage;
        bool isSubscription;
        uint256 subscriptionDuration;
    }

    mapping(uint256 => Content) public contents;
    mapping(uint256 => mapping(address => uint256)) public subscriptionExpiry;

    IERC20 public paymentToken;
    uint256 public platformFeePercentage;

    event ContentUploaded(uint256 indexed tokenId, address indexed creator, uint256 price);
    event ContentPurchased(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _paymentToken,
        uint256 _platformFeePercentage,
        address _lzEndpoint,
        address _delegate
    ) ONFT721(_name, _symbol, _lzEndpoint, _delegate) {
        paymentToken = IERC20(_paymentToken);
        platformFeePercentage = _platformFeePercentage;
        _tokenIdCounter = 0;
    }

    function uploadContent(
        string memory _contentHash,
        uint256 _price,
        uint256 _royaltyPercentage,
        bool _isSubscription,
        uint256 _subscriptionDuration
    ) public {
        require(bytes(_contentHash).length > 0, "Content hash cannot be empty");
        require(_price > 0, "Price must be greater than 0");
        require(_royaltyPercentage <= 100, "Royalty percentage cannot exceed 100%");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        _safeMint(msg.sender, newTokenId);

        contents[newTokenId] = Content({
            creator: payable(msg.sender),
            contentHash: _contentHash,
            price: _price,
            royaltyPercentage: _royaltyPercentage,
            isSubscription: _isSubscription,
            subscriptionDuration: _subscriptionDuration
        });

        emit ContentUploaded(newTokenId, msg.sender, _price);
    }

    function purchaseContent(uint256 _tokenId) public nonReentrant {
        require(_exists(_tokenId), "Content does not exist");
        Content storage content = contents[_tokenId];
        require(paymentToken.balanceOf(msg.sender) >= content.price, "Insufficient balance");

        uint256 platformFee = (content.price * platformFeePercentage) / 100;
        uint256 creatorPayment = content.price - platformFee;

        require(paymentToken.transferFrom(msg.sender, address(this), platformFee), "Platform fee transfer failed");
        require(paymentToken.transferFrom(msg.sender, content.creator, creatorPayment), "Creator payment failed");

        if (content.isSubscription) {
            subscriptionExpiry[_tokenId][msg.sender] = block.timestamp + content.subscriptionDuration;
        } else {
            address previousOwner = ownerOf(_tokenId);
            _beforeTokenTransfer(previousOwner, msg.sender, _tokenId);
            _transfer(ownerOf(_tokenId), msg.sender, _tokenId);
        }

        emit ContentPurchased(_tokenId, msg.sender, content.price);
    }

    function hasAccess(uint256 _tokenId, address _user) public view returns (bool) {
        require(_exists(_tokenId), "Content does not exist");
        Content storage content = contents[_tokenId];
        
        if (content.isSubscription) {
            return subscriptionExpiry[_tokenId][_user] > block.timestamp;
        } else {
            return ownerOf(_tokenId) == _user;
        }
    }

    function getContentDetails(uint256 _tokenId) public view returns (address, string memory, uint256, uint256, bool, uint256) {
        require(_exists(_tokenId), "Content does not exist");
        Content storage content = contents[_tokenId];
        return (content.creator, content.contentHash, content.price, content.royaltyPercentage, content.isSubscription, content.subscriptionDuration);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        require(_exists(_tokenId), "Content does not exist");
        Content storage content = contents[_tokenId];
        return (content.creator, (_salePrice * content.royaltyPercentage) / 100);
    }

    function updateContentPrice(uint256 _tokenId, uint256 _newPrice) public {
        require(_exists(_tokenId), "Content does not exist");
        require(msg.sender == contents[_tokenId].creator, "Only creator can update price");
        contents[_tokenId].price = _newPrice;
    }

    function withdrawPlatformFees() public onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        require(paymentToken.transfer(owner(), balance), "Transfer failed");
    }

   function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        if (contents[tokenId].isSubscription) {
            uint256 remainingTime = subscriptionExpiry[tokenId][from] > block.timestamp ?
                subscriptionExpiry[tokenId][from] - block.timestamp : 0;
            subscriptionExpiry[tokenId][to] = block.timestamp + remainingTime;
            delete subscriptionExpiry[tokenId][from];
        }
    }

    function _debit(address _from, uint256 _tokenId, uint32) internal virtual override {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "ONFT721: send caller is not owner nor approved");
        require(ownerOf(_tokenId) == _from, "ONFT721: send from incorrect owner");
        
        // Call _beforeTokenTransfer before changing ownership
        _beforeTokenTransfer(_from, address(this), _tokenId);
        
        // Burn the token to this contract instead of burning
        _burn(_tokenId);
    }

    function _credit(address _to, uint256 _tokenId, uint32) internal virtual override {
        // Call _beforeTokenTransfer before changing ownership
        _beforeTokenTransfer(address(this), _to, _tokenId);
        
        // Mint the token from this contract to the recipient
        _mint(_to, _tokenId);
    }

    function getCurrentTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }
}