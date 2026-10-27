// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract EscrowMarket {

    enum State { None, Funded, Shipped, Completed, Refunded, Disputed, Resolved }

    // Empaquetado de Structs para ahorrar gas
    struct Deal {
        address buyer;
        uint96  amount;
        address seller;
        State   state;
        uint40  deadline;  
        uint40  shippedAt; 
        bytes32 descriptionHash; 
    }

    uint256 public constant ARBITER_FEE_BPS = 100; // 1%
    uint256 private constant BPS = 10000;

    address public arbiter;
    uint40 public confirmWindow; 

    uint256 public nextDealId;
    mapping(uint256 => Deal) public deals;
    mapping(address => uint256) public credits;

    event DealCreated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint40 deadline,
        bytes32 descriptionHash);
    event DealStateChanged(uint256 indexed id, State state);
    event DisputeResolved(uint256 indexed id, bool releasedToSeller, uint256 arbiterFee);
    event Withdrawal(address indexed account, uint256 amount);

    // MODIFICADORES (Agrupando los require repetitivos)
    modifier inState(uint256 id, State _state) {
        require(deals[id].state == _state, "Estado incorrecto para esta accion");
        _;
    }

    modifier onlyBuyer(uint256 id) {
        require(msg.sender == deals[id].buyer, "Solo el comprador puede llamar a esto");
        _;
    }

    modifier onlySeller(uint256 id) {
        require(msg.sender == deals[id].seller, "Solo el vendedor puede llamar a esto");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Solo el arbitro puede llamar a esto");
        _;
    }

    // ------------------------------------------------------------------

    constructor(address _arbiter, uint40 _confirmWindow) {
        require(_arbiter != address(0), "El arbitro no puede ser la direccion 0");
        require(_confirmWindow > 0, "Ventana de tiempo invalida");
        arbiter = _arbiter;
        confirmWindow = _confirmWindow;
    }

    function createDeal(address _seller, bytes32 _descriptionHash, uint40 _shippingWindow) external payable returns (uint256) {
        require(_seller != address(0) && _seller != msg.sender && _seller != arbiter && msg.sender != arbiter, "Participantes invalidos");
        require(msg.value > 0 && msg.value <= type(uint96).max, "Cantidad invalida");
        require(_shippingWindow > 0, "Ventana de envio invalida");

        uint40 deadline = uint40(block.timestamp) + _shippingWindow; 

        uint256 id = nextDealId;
        
        // Podriamos usar la libreria SafeMath de OpenZeppelin aqui para evitar desbordamientos (overflows), 
        // pero a partir de la version 0.8.0 de Solidity el lenguaje ya hace las comprobaciones matematicas solo.
        nextDealId = id + 1; 

        deals[id] = Deal({
            buyer: msg.sender,
            amount: uint96(msg.value),
            seller: _seller,
            state: State.Funded,
            deadline: deadline,
            shippedAt: 0,
            descriptionHash: _descriptionHash
        });

        emit DealCreated(id, msg.sender, _seller, msg.value, deadline, _descriptionHash);
        return id;
    }

    function markShipped(uint256 id) external onlySeller(id) inState(id, State.Funded) {
        require(block.timestamp <= deals[id].deadline, "El plazo ha expirado");
        
        deals[id].state = State.Shipped;
        deals[id].shippedAt = uint40(block.timestamp);
        emit DealStateChanged(id, State.Shipped);
    }

    function confirmReceipt(uint256 id) external onlyBuyer(id) inState(id, State.Shipped) {
        deals[id].state = State.Completed;
        credits[deals[id].seller] += deals[id].amount;
        emit DealStateChanged(id, State.Completed);
    }

    function releaseAfterTimeout(uint256 id) external onlySeller(id) inState(id, State.Shipped) {
        require(block.timestamp > uint256(deals[id].shippedAt) + confirmWindow, "Plazo de confirmacion aun abierto");

        deals[id].state = State.Completed;
        credits[deals[id].seller] += deals[id].amount;
        emit DealStateChanged(id, State.Completed);
    }

    function claimRefund(uint256 id) external onlyBuyer(id) inState(id, State.Funded) {
        require(block.timestamp > deals[id].deadline, "Aun hay tiempo para el envio");

        deals[id].state = State.Refunded;
        credits[deals[id].buyer] += deals[id].amount;
        emit DealStateChanged(id, State.Refunded);
    }

    function openDispute(uint256 id) external inState(id, State.Shipped) {
        require(msg.sender == deals[id].buyer || msg.sender == deals[id].seller, "No eres participante");
        require(block.timestamp <= uint256(deals[id].shippedAt) + confirmWindow, "Fuera de plazo para disputas");

        deals[id].state = State.Disputed;
        emit DealStateChanged(id, State.Disputed);
    }

    function resolveDispute(uint256 id, bool releaseToSeller) external onlyArbiter inState(id, State.Disputed) {
        deals[id].state = State.Resolved;

        uint256 fee = (uint256(deals[id].amount) * ARBITER_FEE_BPS) / BPS;
        address winner = releaseToSeller ? deals[id].seller : deals[id].buyer;

        uint256 payout = deals[id].amount - fee; 
        credits[winner] += payout;
        if (fee > 0) {
            credits[arbiter] += fee;
        }

        emit DealStateChanged(id, State.Resolved);
        emit DisputeResolved(id, releaseToSeller, fee);
    }

    function withdraw() external {
        uint256 amount = credits[msg.sender];
        require(amount > 0, "Nada que retirar");

        credits[msg.sender] = 0; 
        
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Fallo al transferir");

        emit Withdrawal(msg.sender, amount);
    }
}