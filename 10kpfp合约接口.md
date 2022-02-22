# 10kpfp合约接口

**Factory 合约地址**

Rinkeby: 0x1Bb37d2E0627646c47b1eECf1A50CB3F2C40aCDb	





## 1. 工厂合约

### 1.1 创建 10kpfp NFT合约

**Function**: `createNFT`

**MethodID**: `f5699b81`

**Description**:   通过 Factory 合约创建 10kpfp NFT 合约

| Parameter                 | Type    | Description                                                  |
| ------------------------- | ------- | ------------------------------------------------------------ |
| name_                     | string  | NFT Name                                                     |
| symbol_                   | string  | NFT Symbol                                                   |
| notRevealedURI_           | string  | notRevealedURI && Contract-level metadata. URL for the storefront-level metadata for contract |
| maxBatchSize_             | uint256 | mint时每个地址的最大值&&每个用户最大mint数量                 |
| collectionSize_           | uint256 | 该 nft 集合token的最大供应量                                 |
| amountForDevsAndPlatform_ | uint256 | dev和platform可mint的数量                                    |
| amountForPlatform_        | uint256 | 划分给platform的数量, 小于amountForDevsAndPlatform_          |
| signer_                   | address | NFT mint所需的签名公钥                                       |



**Event-fields & Signature:**

```
event CreateNFT(address indexed nftAddress);

Text Signature: "CreateNFT(address indexed)"
Event Hex Signature: 012b47e3f53ba43cf4658ac954147415baf5c6c94761af3bfda93607513f234a
```

| Field      | Type    | Description         | isIndexed |
| ---------- | ------- | ------------------- | --------- |
| nftAddress | address | 新创建的nft Address | true      |





### 1.2 提取剩余 ERC20 Token

**Function**: `withdrawToken`

**MethodID**: `01e33667`

**Description**:   提取 Factory 中的 erc20 代币

| Parameter    | Type    | Description       |
| ------------ | ------- | ----------------- |
| token_       | address | ERC20 Token Addre |
| destination_ | string  | 目标地址          |
| amount_      | string  | 提取数量          |



### 1.3 提取剩余 ETH

**Function**: `withdrawEth`

**MethodID**: `1b9a91a4`

**Description**:   提取 Factory 中的 erc20 代币

| Parameter    | Type   | Description |
| ------------ | ------ | ----------- |
| destination_ | string | 目标地址    |
| amount_      | string | 提取数量    |



## 2. NFT合约

### 2.1 设置 Base URI

**Function**: `setBaseURI`

**MethodID**: `55f804b3`

**Description**:   设置 NFT Base URI

| Parameter | Type   | Description |
| --------- | ------ | ----------- |
| baseURI   | string | Base URI    |



### 2.2 设置盲盒URI

**Function**: `setNotRevealedURI`

**MethodID**: `f2c4ce1e`

**Description**:   设置 NFT Base URI

| Parameter      | Type   | Description |
| -------------- | ------ | ----------- |
| notRevealedURI | string | 盲盒 URI    |

### 2.3 冻结 Token URI

**Function**: `freezeTokenURI`

**MethodID**: `ba4695fd`

**Description**:   冻结 Token URI

| Parameter | Type | Description |
| --------- | ---- | ----------- |
|           |      |             |

### 2.4 揭示盲盒URI

**Function**: `reveal`

**MethodID**: `a475b5dd`

**Description**:  揭示盲盒URI

| Parameter | Type | Description |
| --------- | ---- | ----------- |
|           |      |             |

### 2.4 查询 Token URI

**Function**: `tokenURI`

**MethodID**:  `c87b56dd`

**Type:  ** `Read`

**Description**: 查询某个指定 ID 的 Token URI

| Parameter | Type    | Description   |
| --------- | ------- | ------------- |
| tokenId   | uint256 | 指定 Token ID |

**Return Value**: 

| Parameter | Type   | Description                                                  |
| --------- | ------ | ------------------------------------------------------------ |
| token uri | string | 未进行揭示时返回盲盒URI<br />揭示后<br />1. 已设置 baseUri 返回 baseUri + 随机数级联<br />2.未设置 baseUri 返回默认值 |

### 2.4 更新预售白名单及价格

**Function**: `updatePresaleInfo`

**MethodID**: `f9236ff6`

**Description**:   更新 MerkleRoot 以支持白名单, 开启白名单预售

| Parameter          | Type    | Description             |
| ------------------ | ------- | ----------------------- |
| newBalanceTreeRoot | bytes32 | 新的 MerkleRoot         |
| mintlistPriceWei   | uint256 | 白名单预售价格 单位 wei |

### 2.5 白名单预售Mint

**Function**: `preSalesMint`

**MethodID**: `787fd082`

**Description**:   白名单预售Mint方法

| Parameter    | Type      | Description               |
| ------------ | --------- | ------------------------- |
| index        | uint256   | 白名单  index             |
| thisTimeMint | uint256   | 本次mint数量              |
| maxMint      | uint256   | 该用户白名单最大mint数量  |
| merkleProof  | bytes32[] | merkleProof 验证路径Proof |
| salt         | string    | 盐值 随机 定期更换        |
| signature    | bytes     | 签名结果                  |
| eth amount   | eth       | 发送的eth数量             |

**Event-fields & Signature:**

```
event PreSalesMint(uint256 index, address account, uint256 amount, uint256 maxMint);

Text Signature: "PreSalesMint(uint256,address,uint256,uint256)"
Event Hex Signature: 595aaede9de4a7851636cd278316b0c860b678208bab75fdfbb651d01c0b19d5
```

| Field   | Type    | Description   | isIndexed |
| ------- | ------- | ------------- | --------- |
| index   | uint256 | 白名单 index  | true      |
| account | address | mint 用户地址 | true      |
| amount  | uint256 | mint数量      | false     |
| maxMint | uint256 | 最大mint数量  | false     |



### 2.6 设置mint所需公钥

**Function**: `setSigner`

**MethodID**: `6c19e783`

**Description**:   设置 mint 公钥地址

| Parameter | Type    | Description       |
| --------- | ------- | ----------------- |
| signer_   | Address | mint 所需公钥地址 |





### 2.7 公售(荷兰拍)设置拍卖开始时间及相关参数

**Function**: `endPublicSalesAndSetupAuctionSaleInfo`

**MethodID**: `e26d5f4a`

**Description**:   设置荷兰拍参数, 并结束固定价格的公售

| Parameter                | Type    | Description      |
| ------------------------ | ------- | ---------------- |
| auctionSaleStartTime_    | uint32  | 开始时间戳(秒级) |
| auctionStartPrice_       | uint128 | 起始价格         |
| auctionEndPrice_         | uint128 | 结束价格         |
| auctionPriceCurveLength_ | uint64  | 拍卖时长         |
| auctionDropInterval_     | uint64  | 拍卖下降间隔     |



### 2.8 公售(荷兰拍) Mint 

**Function**: `auctionMint`

**MethodID**: `e26d5f4a`

**Description**:   荷兰拍 mint 方法

| Parameter | Type    | Description      |
| --------- | ------- | ---------------- |
| quantity  | uint32  | 开始时间戳(秒级) |
| salt      | uint128 | 起始价格         |
| signature | uint128 | 结束价格         |

**Event-fields & Signature:**

```
event AuctionMint(address indexed user, uint256 number, uint256 totalCost);

Text Signature: "AuctionMint(address indexed,uint256,uint256)"
Event Hex Signature: dec21920125339eda7ee3bad222a20df6041eb3a6dcef59e716c87bbbf485360
```

| Field     | Type    | Description   | isIndexed |
| --------- | ------- | ------------- | --------- |
| user      | address | mint 用户地址 | true      |
| number    | uint256 | 用户mint数量  | false     |
| totalCost | uint256 | 总价          | false     |



### 2.9 公售(固定价格) 设置 && 非拍卖销售设置

**Function**: `endAuctionAndSetupPublicSaleInfo`

**MethodID**: `4ef73838`

**Description**:   公售(固定价格) 参数设置, 并强制关闭荷兰拍

| Parameter           | Type    | Description  |
| ------------------- | ------- | ------------ |
| publicPriceWei      | uint128 | 公售固定价格 |
| publicSaleStartTime | uint128 | 公售开始时间 |



### 2.10 公售(固定价格) 设置 && 非拍卖销售设置

**Function**: `publicSaleMint`

**MethodID**: `299c8989`

**Description**:   公售(固定价格)  mint 方法

| Parameter | Type    | Description        |
| --------- | ------- | ------------------ |
| quantity  | uint128 | 公售固定价格       |
| salt      | string  | 盐值 随机 定期更换 |
| signature | bytes   | 签名结果           |

**Event-fields & Signature:**

```
event PublicSaleMint(address indexed user, uint256 number, uint256 totalCost);

Text Signature: "PublicSaleMint(address indexed,uint256,uint256)"
Event Hex Signature: ecd35b7ff452057eb5131aa07239d81231e8728161ec2dc0ff51c92625f1f8ba
```

| Field     | Type    | Description   | isIndexed |
| --------- | ------- | ------------- | --------- |
| user      | address | mint 用户地址 | true      |
| number    | uint256 | 用户mint数量  | false     |
| totalCost | uint256 | 总价          | false     |

