# CLAUDE.md — Contexte projet raspberry-syslog-certbot

## Qui je suis

Je suis Claude, assistant de Novolink (SARL). Ce projet est développé
par Adrien (Novolink) en collaboration avec moi. Lis ce fichier en entier
avant de toucher quoi que ce soit.

---

## Contexte Novolink

Novolink est un MSP (prestataire informatique) qui gère l'infrastructure
de clients professionnels, notamment des hôtels. L'infrastructure centrale
se compose de :

- **PVE VL** (Villeneuve-Loubet) : hyperviseur Proxmox, Dell R640
- **PVE SL** (Saint-Laurent-du-Var) : hyperviseur Proxmox, Dell R640
- **VPS OVH** : HAProxy + Certbot + Qdevice Corosync
- **VM112** : serveur Zabbix (monitoring centralisé)
- Réseau : MikroTik CCR2004, tunnels WireGuard, EOIPv6

---

## Ce qu'est ce projet

Un produit déployé chez les clients hôtel de Novolink. Chaque client reçoit
une **Raspberry Pi 5 8GB** avec NVMe 1TB, connectée au réseau local du client.

### Rôle de la Raspberry Pi sur chaque site client

1. **Serveur syslog** — reçoit les logs de tous les équipements réseau
   (APs TP-Link Omada, switches, routeurs) sur le port 514 UDP/TCP
2. **Interface web** — permet au client de consulter et télécharger ses logs
3. **Push certificat SSL** — injecte automatiquement un certificat Let's Encrypt
   dans le contrôleur Omada local (OC200 ou OC300) pour corriger les
   avertissements SSL sur les appareils Apple au portail captif
4. **Agent Zabbix** — remonte l'état de la Pi vers le serveur Zabbix de Novolink

### Contexte réseau sur site client

- Contrôleur Omada OC200 ou OC300 sur chaque site (IP typique : 192.168.0.2)
- Raspberry Pi (IP typique : 192.168.0.3)
- WireGuard géré par le routeur Omada (pas par la Pi)
- La Pi est donc joignable depuis Novolink via ce tunnel

---

## Architecture technique actuelle
