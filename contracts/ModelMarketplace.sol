// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ModelMarketplace is ERC721, ReentrancyGuard {
    using Counters for Counters.Counter;

    struct ModelListing {
        string modelHash;
        uint256 price;
        address seller;
        bool isActive;
        string metadata;
        uint256 rating;
        uint256 ratingCount;
    }

    struct Order {
        address buyer;
        address seller;
        uint256 modelId;
        uint256 price;
        uint256 timestamp;
        OrderStatus status;
    }

    enum OrderStatus {
        Pending,
        Completed,
        Refunded,
        Disputed
    }

    Counters.Counter private _tokenIds;
    Counters.Counter private _orderIds;

    mapping(uint256 => ModelListing) public listings;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userOrders;

    uint256 public platformFee = 25; // 2.5%
    address public feeCollector;

    event ModelListed(uint256 indexed tokenId, address seller, uint256 price);
    event ModelSold(uint256 indexed tokenId, address buyer, uint256 price);
    event ModelRated(uint256 indexed tokenId, address rater, uint256 rating);

    constructor() ERC721("AI Model NFT", "AIMODEL") {
        feeCollector = msg.sender;
    }

    function listModel(
        string memory _modelHash,
        uint256 _price,
        string memory _metadata
    ) external returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _safeMint(msg.sender, newTokenId);

        listings[newTokenId] = ModelListing({
            modelHash: _modelHash,
            price: _price,
            seller: msg.sender,
            isActive: true,
            metadata: _metadata,
            rating: 0,
            ratingCount: 0
        });

        userListings[msg.sender].push(newTokenId);
        emit ModelListed(newTokenId, msg.sender, _price);
        return newTokenId;
    }

    function purchaseModel(uint256 _tokenId) external payable nonReentrant {
        ModelListing storage listing = listings[_tokenId];
        require(listing.isActive, "Model not available");
        require(msg.value >= listing.price, "Insufficient payment");

        _orderIds.increment();
        uint256 orderId = _orderIds.current();

        // Calculate platform fee
        uint256 fee = (listing.price * platformFee) / 1000;
        uint256 sellerAmount = listing.price - fee;

        // Transfer funds
        payable(feeCollector).transfer(fee);
        payable(listing.seller).transfer(sellerAmount);

        // Create order
        orders[orderId] = Order({
            buyer: msg.sender,
            seller: listing.seller,
            modelId: _tokenId,
            price: listing.price,
            timestamp: block.timestamp,
            status: OrderStatus.Completed
        });

        // Transfer NFT
        _transfer(listing.seller, msg.sender, _tokenId);
        listing.isActive = false;

        userOrders[msg.sender].push(orderId);
        emit ModelSold(_tokenId, msg.sender, listing.price);
    }

    function rateModel(uint256 _tokenId, uint256 _rating) external {
        require(_rating >= 1 && _rating <= 5, "Invalid rating");
        require(ownerOf(_tokenId) == msg.sender, "Not model owner");

        ModelListing storage listing = listings[_tokenId];
        listing.rating = ((listing.rating * listing.ratingCount) + _rating) / 
            (listing.ratingCount + 1);
        listing.ratingCount++;

        emit ModelRated(_tokenId, msg.sender, _rating);
    }

    function getModelDetails(uint256 _tokenId)
        external view returns (
            string memory modelHash,
            uint256 price,
            address seller,
            bool isActive,
            string memory metadata,
            uint256 rating,
            uint256 ratingCount
        )
    {
        ModelListing storage listing = listings[_tokenId];
        return (
            listing.modelHash,
            listing.price,
            listing.seller,
            listing.isActive,
            listing.metadata,
            listing.rating,
            listing.ratingCount
        );
    }

    function getUserListings(address _user)
        external view returns (uint256[] memory)
    {
        return userListings[_user];
    }

    function getUserOrders(address _user)
        external view returns (uint256[] memory)
    {
        return userOrders[_user];
    }

    function updatePlatformFee(uint256 _newFee) external {
        require(msg.sender == feeCollector, "Not authorized");
        require(_newFee <= 50, "Fee too high"); // Max 5%
        platformFee = _newFee;
    }
} 