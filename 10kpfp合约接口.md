# 10kpfp合约接口

## 1. 工厂合约

### 1.1 创建 10kpfp NFT合约

**Function**: `createNFT`

**MethodID**: `f5699b81`

**Description**:   通过 Factory 合约创建 10kpfp NFT 合约

| Parameter               | Type    | Description                                                  |
| ----------------------- | ------- | ------------------------------------------------------------ |
| name_                   | string  | NFT Name                                                     |
| symbol_                 | string  | NFT Symbol                                                   |
| contractURI_            | string  | Contract-level metadata. URL for the storefront-level metadata for contract. |
| maxBatchSize_           | uint256 | mint时每个地址的最大值&&每个用户最大mint数量                 |
| collectionSize_         | uint256 | 该 nft 集合token的最大供应量                                 |
| amountForAuctionAndDev_ | uint256 |                                                              |
| amountForDevs_          | uint256 | dev可直接mint的数量                                          |



### 1.2 提取剩余Link

**Function**: `withdrawLink`

**MethodID**: `54b7faae`

**Description**:   提取 Factory 中的Link代币

| Parameter   | Type   | Description |
| ----------- | ------ | ----------- |
| destination | string | NFT Name    |
| amount      | string | NFT Symbol  |



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
| token uri | string | 未进行揭示时返回盲盒URI<br />揭示后<br />1. 已设置 baseUri 返回 baseUri + 随机数级联<br />2.未设置 baseUri 返回单独的 tokenUri (有默认值) |

### 2.4 更新白名单

**Function**: `updateMerkleRoot`

**MethodID**: `4783f0ef`

**Description**:   更新 MerkleRoot 以支持白名单, 开启白名单预售

| Parameter     | Type    | Description     |
| ------------- | ------- | --------------- |
| newMerkleRoot | bytes32 | 新的 MerkleRoot |

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



### 2.6 设置公售公钥

**Function**: `setPublicSaleSigner`

**MethodID**: `90028083`

**Description**:   设置公售公钥

| Parameter     | Type    | Description    |
| ------------- | ------- | -------------- |
| signerAddress | Address | Signer公钥地址 |

### 



### 2.7 公售(荷兰拍)设置拍卖开始时间及相关参数

**Function**: `setAuctionConfig`

**MethodID**: `ed10a6b9`

**Description**:   荷兰拍设置

| Parameter               | Type    | Description      |
| ----------------------- | ------- | ---------------- |
| timestamp               | uint32  | 开始时间戳(秒级) |
| auctionStartPrice       | uint128 | 起始价格         |
| auctionEndPrice         | uint128 | 结束价格         |
| auctionPriceCurveLength | uint64  | 拍卖时长         |
| auctionDropInterval     | uint64  | 拍卖下降间隔     |
| signature               | bytes   | signer 签名      |

### 

### 2.8 公售(固定价格) 设置 && 非拍卖销售设置

**Function**: `endAuctionAndSetupNonAuctionSaleInfo`

**MethodID**: `16e6e15a`

**Description**:   公售(固定价格) 设置, 以及部分非荷兰拍类型的设置,  并强制关闭荷兰拍

| Parameter           | Type    | Description                         |
| ------------------- | ------- | ----------------------------------- |
| mintlistPriceWei    | uint32  | 白名单价格, 设置为0可关闭白名单mint |
| publicPriceWei      | uint128 | 公售固定价格                        |
| publicSaleStartTime | uint128 | 公售开始时间                        |
| signature           | bytes   | signer 签名                         |

### 

