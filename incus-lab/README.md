# Lab 3 máy Linux kết hợp Incus Container & QEMU VM trên Ubuntu WSL

Bộ script tạo **3 máy Linux độc lập (mỗi máy 1 CPU, 1 GiB RAM)**:
- **`node1`, `node2`**: Chạy bằng **Incus system container** (khởi động tức thì, siêu nhẹ).
- **`node3`**: Chạy bằng **máy ảo QEMU độc lập** (`qemu-system-x86_64`) với Ubuntu 24.04 Cloud Image (kernel riêng, hỗ trợ nạp kernel module, sysctl tùy biến).
- Cả 3 máy đều nối chung vào 2 switch mạng ảo (`mgmtbr0` và `labbr0`), giao tiếp thông suốt với nhau.

## Sơ đồ

```
                 Windows  ──  Ubuntu WSL
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        │                                                     │
   mgmtbr0 10.20.20.0/24 (DHCP + NAT → Internet)        labbr0 (switch L2 thuần)
        │  eth0                                          │  eth1   KHÔNG Internet
   ┌────┴────┬───────────┐                          ┌────┴────┬───────────┐
   │         │           │                          │         │           │
 eth0       eth0     tap-mgmt3                    eth1       eth1     tap-lab3
   │         │           │                          │         │           │
┌──┴──┐   ┌──┴──┐   ┌────┴────┐                10.10.10.11 10.10.10.12 10.10.10.13
│node1│   │node2│   │  node3  │                    node1     node2       node3
│Incus│   │Incus│   │  QEMU   │                    (Incus)   (Incus)    (QEMU)
└─────┘   └─────┘   └─────────┘
 1 CPU     1 CPU     1 CPU
 1 GiB     1 GiB     1 GiB
```

* **eth0 / mgmtbr0** — mạng quản trị: dùng để `apt install`, tải package. Có DHCP và NAT.
* **eth1 / labbr0** — mạng thực hành: bridge L2 thuần, host **không** có IP trên đó, không DHCP, không NAT. 3 máy chỉ thấy nhau, hoàn toàn cắt khỏi Internet và khỏi LAN vật lý.

---

## Cách chạy

**Cách 1 — nhanh nhất:** double-click **`RUN-LAB.cmd`** từ Windows.  
Nó gọi Ubuntu WSL, tự động cấu hình systemd, chạy tuần tự các bước cài đặt và khởi động cả 3 node.

**Cách 2 — chạy trong Ubuntu WSL:**
```bash
cd /mnt/c/Training/Windows19S/incus-lab
chmod +x *.sh
./run-all.sh                  # chạy tự động: 01 -> 02 -> 02-qemu -> 03

# hoặc chạy từng bước:
./01-setup-incus.sh           # Cài Incus + khởi tạo storage pool
./02-create-lab.sh            # Tạo bridge và 2 node Incus (node1, node2)
./02-create-qemu-node3.sh     # Tạo card TAP và khởi động VM QEMU (node3)
./03-verify.sh                # Kiểm tra kết nối ping qua lại giữa cả 3 node
```

> **Tăng tốc QEMU (Tùy chọn khuyến nghị):**  
> Để QEMU node3 chạy ở tốc độ phần cứng KVM (nhanh hơn nhiều lần so với giả lập TCG), bạn chỉ cần thêm vào `%USERPROFILE%\.wslconfig` trên Windows:
> ```ini
> [wsl2]
> nestedVirtualization=true
> ```
> rồi chạy `wsl --shutdown` từ PowerShell. Script `02-create-qemu-node3.sh` sẽ tự động kích hoạt KVM khi tìm thấy `/dev/kvm`.

---

## Dùng hằng ngày

### 1. Quản trị node1, node2 (Incus)
```bash
sudo incus list                        # xem trạng thái 2 node Incus
sudo incus exec node1 -- bash          # vào shell node1 trực tiếp
sudo incus exec node2 -- bash          # vào shell node2 trực tiếp
sudo incus stop node1                  # tắt node1
sudo incus start node1                 # bật node1
```

### 2. Quản trị node3 (QEMU)
```bash
# Cách 1: SSH từ node1/node2 hoặc từ WSL (user: ubuntu, pass: ubuntu)
ssh ubuntu@10.10.10.13

# Cách 2: Vào trực tiếp Serial Console của QEMU
./console-node3.sh                     # hoặc: telnet 127.0.0.1 4444 (thoát bằng Ctrl+] rồi gõ quit)

# Tắt / Bật lại node3:
./stop-node3.sh                        # tắt QEMU node3
./start-node3.sh                       # bật lại QEMU node3
```

---

## Bài thực hành mạng gợi ý (Incus ⇄ QEMU)

1. **Kiểm tra tương tác dị thể (Container vs VM)**:
   - Trên node3 (QEMU VM): `tcpdump -ni eth1 icmp`
   - Trên node1 (Incus container): `ping -c 3 10.10.10.13`
2. **Biến node3 (QEMU VM) thành Router**:
   - Bật định tuyến trong kernel thật của node3: `sudo sysctl -w net.ipv4.ip_forward=1`
   - Cấu hình static route trên node1 và node2 trỏ qua node3.
3. **Thực hành Tường lửa / iptables / nftables**:
   - Viết luật nftables trên node3 chặn gói ICMP từ node1 nhưng cho phép từ node2.
4. **Đo hiệu năng băng thông**:
   - Chạy `iperf3 -s` trên node3 (QEMU) và `iperf3 -c 10.10.10.13` từ node1 (Incus).

---

## Xoá lab

```bash
./99-destroy.sh     # dừng QEMU node3, xoá TAP devices, xoá node1, node2 và 2 mạng bridge
```
