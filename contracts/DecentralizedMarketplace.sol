// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DecentralizedMarketplace is AccessControl, ReentrancyGuard, ERC721 {
    bytes32 public constant MARKETPLACE_ADMIN_ROLE = keccak256("MARKETPLACE_ADMIN_ROLE");

    struct ModelListing {
        uint256 tokenId;
        string modelHash;
        string metadata;
        uint256 price;
        address seller;
        uint256 creationTime;
        bool isActive;
        uint256 rating;
        uint256 ratingCount;
        License license;
    }

    struct Order {
        uint256 orderId;
        uint256 tokenId;
        address buyer;
        uint256 price;
        uint256 timestamp;
        OrderStatus status;
    }

    struct License {
        string terms;
        bool allowsCommercial;
        bool allowsModification;
        uint256 duration;
    }

    enum OrderStatus {
        Created,
        Completed,
        Refunded,
        Disputed
    }

    mapping(uint256 => ModelListing) public listings;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userPurchases;
    
    uint256 public platformFee;
    uint256 public listingCount;
    uint256 public orderCount;

    event ModelListed(
        uint256 indexed tokenId,
        string modelHash,
        uint256 price,
        address seller
    );
    event OrderCreated(
        uint256 indexed orderId,
        uint256 indexed tokenId,
        address buyer,
        uint256 price
    );
    event OrderCompleted(
        uint256 indexed orderId,
        uint256 indexed tokenId
    );
    event ModelRated(
        uint256 indexed tokenId,
        address indexed rater,
        uint256 rating
    );

    constructor(uint256 _platformFee) ERC721("AI Model NFT", "AIMODEL") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MARKETPLACE_ADMIN_ROLE, msg.sender);
        platformFee = _platformFee;
    }

    function listModel(
        string memory _modelHash,
        string memory _metadata,
        uint256 _price,
        License memory _license
    ) external nonReentrant returns (uint256) {
        require(bytes(_modelHash).length > 0, "Invalid model hash");
        require(_price > 0, "Invalid price");

        listingCount++;
        uint256 tokenId = listingCount;

        _mint(msg.sender, tokenId);

        listings[tokenId] = ModelListing({
            tokenId: tokenId,
            modelHash: _modelHash,
            metadata: _metadata,
            price: _price,
            seller: msg.sender,
            creationTime: block.timestamp,
            isActive: true,
            rating: 0,
            ratingCount: 0,
            license: _license
        });

        userListings[msg.sender].push(tokenId);

        emit ModelListed(tokenId, _modelHash, _price, msg.sender);
        return tokenId;
    }

    function purchaseModel(uint256 _tokenId)
        external
        payable
        nonReentrant
    {
        ModelListing storage listing = listings[_tokenId];
        require(listing.isActive, "Listing not active");
        require(msg.value >= listing.price, "Insufficient payment");

        orderCount++;
        Order storage order = orders[orderCount];
        order.orderId = orderCount;
        order.tokenId = _tokenId;
        order.buyer = msg.sender;
        order.price = listing.price;
        order.timestamp = block.timestamp;
        order.status = OrderStatus.Created;

        userPurchases[msg.sender].push(_tokenId);

        // Transfer NFT
        _transfer(listing.seller, msg.sender, _tokenId);

        // Process payment
        uint256 fee = (listing.price * platformFee) / 100;
        uint256 sellerAmount = listing.price - fee;
        
        payable(listing.seller).transfer(sellerAmount);
        payable(owner()).transfer(fee);

        order.status = OrderStatus.Completed;

        emit OrderCompleted(orderCount, _tokenId);
    }

    function rateModel(
        uint256 _tokenId,
        uint256 _rating
    ) external {
        require(_rating >= 1 && _rating <= 5, "Invalid rating");
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");

        ModelListing storage listing = listings[_tokenId];
        listing.rating = ((listing.rating * listing.ratingCount) + _rating) /
            (listing.ratingCount + 1);
        listing.ratingCount++;

        emit ModelRated(_tokenId, msg.sender, _rating);
    }

    function updateListing(
        uint256 _tokenId,
        uint256 _newPrice,
        bool _isActive
    ) external {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        
        ModelListing storage listing = listings[_tokenId];
        listing.price = _newPrice;
        listing.isActive = _isActive;
    }

    function updateLicense(
        uint256 _tokenId,
        License memory _newLicense
    ) external {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        
        listings[_tokenId].license = _newLicense;
    }

    function setPlatformFee(uint256 _newFee)
        external
        onlyRole(MARKETPLACE_ADMIN_ROLE)
    {
        require(_newFee <= 100, "Invalid fee percentage");
        platformFee = _newFee;
    }

    function getUserListings(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userListings[_user];
    }

    function getUserPurchases(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userPurchases[_user];
    }

    function getModelDetails(uint256 _tokenId)
        external
        view
        returns (
            string memory modelHash,
            string memory metadata,
            uint256 price,
            address seller,
            bool isActive,
            uint256 rating,
            uint256 ratingCount,
            License memory license
        )
    {
        ModelListing storage listing = listings[_tokenId];
        return (
            listing.modelHash,
            listing.metadata,
            listing.price,
            listing.seller,
            listing.isActive,
            listing.rating,
            listing.ratingCount,
            listing.license
        );
    }

    function getOrderDetails(uint256 _orderId)
        external
        view
        returns (
            uint256 tokenId,
            address buyer,
            uint256 price,
            uint256 timestamp,
            OrderStatus status
        )
    {
        Order storage order = orders[_orderId];
        return (
            order.tokenId,
            order.buyer,
            order.price,
            order.timestamp,
            order.status
        );
    }
} 