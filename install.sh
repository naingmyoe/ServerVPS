#!/bin/bash

set -e

echo "=========================================="
echo "   VPS Tracker Telegram Bot Installer     "
echo "=========================================="
echo ""

# ၁. Bot Token နှင့် Admin ID မေးမြန်းခြင်း
read -p "👉 Telegram Bot Token ကို ရိုက်ထည့်ပါ: " BOT_TOKEN
read -p "👉 Admin Telegram Numeric ID ကို ရိုက်ထည့်ပါ: " ADMIN_ID

if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
    echo "❌ Bot Token သို့မဟုတ် Admin ID မပြည့်စုံပါ။ Installation ကို ရပ်ဆိုင်းလိုက်ပါပြီ။"
    exit 1
fi

echo ""
echo "🔄 System Packages များ Update လုပ်နေပါသည်..."
sudo apt update && sudo apt upgrade -y

# မလိုအပ်သော APT Packages များကို အလိုအလျောက် Clean လုပ်ခြင်း
sudo apt autoremove -y

echo "🔄 Python3, PIP နှင့် dependencies များ Install လုပ်နေပါသည်..."
sudo apt install -y python3 python3-pip python3-venv sqlite3 curl

# PM2 Install (Terminal ပိတ်ထားလည်း background တွင် 24/7 run ထားနိုင်ရန်)
if ! command -v pm2 &> /dev/null
then
    echo "🔄 PM2 Process Manager Install လုပ်နေပါသည်..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
    sudo npm install pm2 -g
fi

# ၂. Python Virtual Environment (venv) အသစ်ပြန်လည် ဖန်တီးခြင်း
echo "🔄 Python Virtual Environment (venv) သန့်သန့် ဖန်တီးနေပါသည်..."
rm -rf venv
python3 -m venv --without-pip venv
source venv/bin/activate
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
rm get-pip.py

echo "🔄 Python Dependencies (python-telegram-bot) Install လုပ်နေပါသည်..."
# PEP 668 / Debian System Package Error ကို ကျော်လွန်ရန် --break-system-packages သုံးထားပါသည်
pip install --upgrade pip
pip install python-telegram-bot --break-system-packages

# ၃. bot.py File ကို အလိုအလျောက် ရေးသားဖန်တီးခြင်း
echo "🔄 bot.py ဖိုင်ကို ရေးသားနေပါသည်..."

cat << 'EOF' > bot.py
import logging
import sqlite3
from datetime import datetime
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup, 
    ReplyKeyboardMarkup, KeyboardButton
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler, 
    MessageHandler, ConversationHandler, filters, ContextTypes
)

# Logging Setup
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

# Configuration Variables
ADMIN_ID = REPLACE_ADMIN_ID
TOKEN = "REPLACE_BOT_TOKEN"

# Conversation States
(
    WAIT_OWNER, WAIT_NAME, WAIT_IP, WAIT_USER, 
    WAIT_PASS, WAIT_LINK, WAIT_EXPIRE, WAIT_REMARK,
    WAIT_EDIT_VALUE
) = range(9)

def init_db():
    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_name TEXT,
            server_name TEXT,
            ip_address TEXT,
            username TEXT,
            password TEXT,
            server_link TEXT,
            expire_date TEXT,
            remark TEXT
        )
    ''')
    conn.commit()
    conn.close()

def get_remaining_days(expire_date_str):
    try:
        expire_date = datetime.strptime(expire_date_str, "%Y-%m-%d").date()
        today = datetime.now().date()
        return (expire_date - today).days
    except Exception:
        return "N/A"

def is_admin(user_id: int) -> bool:
    return user_id == ADMIN_ID

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("⛔️ ခွင့်ပြုချက်မရှိပါ။ သင်သည် Admin မဟုတ်ပါသဖြင့် ဤ Bot ကို အသုံးပြုခွင့်မရှိပါ။")
        return

    keyboard = [
        [KeyboardButton("➕ Server အသစ်ထည့်ရန်")],
        [KeyboardButton("👥 User အလိုက်ကြည့်ရန်"), KeyboardButton("🌐 Server အားလုံးကြည့်ရန်")]
    ]
    reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

    await update.message.reply_text(
        "👋 **မင်္ဂလာပါ Admin!**\n\nVPS Server များ စီမံခန့်ခွဲရန် အောက်ပါ Menu ခလုတ်များကို အသုံးပြုနိုင်ပါသည်။",
        reply_markup=reply_markup,
        parse_mode="Markdown"
    )

async def start_add(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("⛔️ ခွင့်ပြုချက်မရှိပါ။")
        return ConversationHandler.END

    await update.message.reply_text("➕ **Server အသစ်ထည့်သွင်းခြင်း**\n\nပိုင်ရှင်အမည် (Owner Name) ရိုက်ထည့်ပါ:")
    return WAIT_OWNER

async def set_owner(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['owner'] = update.message.text
    await update.message.reply_text("🖥 Server Name ရိုက်ထည့်ပါ:")
    return WAIT_NAME

async def set_name(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['name'] = update.message.text
    await update.message.reply_text("🌐 IP Address ရိုက်ထည့်ပါ (မရှိပါက - ဟုရိုက်ပါ):")
    return WAIT_IP

async def set_ip(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['ip'] = update.message.text
    await update.message.reply_text("👤 Username ရိုက်ထည့်ပါ (ဥပမာ- root):")
    return WAIT_USER

async def set_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['user'] = update.message.text
    await update.message.reply_text("🔑 Password ရိုက်ထည့်ပါ:")
    return WAIT_PASS

async def set_pass(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['pass'] = update.message.text
    await update.message.reply_text("🔗 Server Link / Provider URL ရိုက်ထည့်ပါ (မရှိပါက - ဟုရိုက်ပါ):")
    return WAIT_LINK

async def set_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['link'] = update.message.text
    await update.message.reply_text("📅 Expire Date ရိုက်ထည့်ပါ (ပုံစံ: YYYY-MM-DD ဥပမာ- 2026-12-31):")
    return WAIT_EXPIRE

async def set_expire(update: Update, context: ContextTypes.DEFAULT_TYPE):
    expire = update.message.text
    try:
        datetime.strptime(expire, "%Y-%m-%d")
    except ValueError:
        await update.message.reply_text("❌ ရက်စွဲပုံစံ မှားယွင်းနေပါသည်။ YYYY-MM-DD ပုံစံဖြင့် ပြန်ရိုက်ပါ:")
        return WAIT_EXPIRE
    
    context.user_data['expire'] = expire
    await update.message.reply_text("📝 Remark / မှတ်ချက် ရိုက်ထည့်ပါ (မရှိပါက - ဟုရိုက်ပါ):")
    return WAIT_REMARK

async def set_remark(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['remark'] = update.message.text
    
    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO servers (owner_name, server_name, ip_address, username, password, server_link, expire_date, remark)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        context.user_data['owner'], context.user_data['name'], context.user_data['ip'],
        context.user_data['user'], context.user_data['pass'], context.user_data['link'],
        context.user_data['expire'], context.user_data['remark']
    ))
    conn.commit()
    conn.close()

    await update.message.reply_text("✅ **Server အချက်အလက်များကို အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ!**", parse_mode="Markdown")
    return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("❌ လုပ်ဆောင်ချက်ကို ဖျက်သိမ်းလိုက်ပါပြီ။")
    return ConversationHandler.END

async def list_users(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("⛔️ ခွင့်ပြုချက်မရှိပါ။")
        return

    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT owner_name FROM servers")
    rows = cursor.fetchall()
    conn.close()

    if not rows:
        await update.message.reply_text("ℹ️ မည်သည့် Server အချက်အလက်မျှ မရှိသေးပါ။")
        return

    keyboard = []
    for row in rows:
        owner = row[0]
        keyboard.append([InlineKeyboardButton(f"👤 {owner}", callback_data=f"user_{owner}")])

    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text("👇 Server ကြည့်လိုသည့် **User / Owner** ကို ရွေးချယ်ပါ:", reply_markup=reply_markup, parse_mode="Markdown")

async def list_all_servers(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("⛔️ ခွင့်ပြုချက်မရှိပါ။")
        return

    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()
    cursor.execute("SELECT id, owner_name, server_name, ip_address FROM servers ORDER BY expire_date ASC")
    servers = cursor.fetchall()
    conn.close()

    if not servers:
        await update.message.reply_text("ℹ️ မည်သည့် Server အချက်အလက်မျှ မရှိသေးပါ။")
        return

    keyboard = []
    for s in servers:
        s_id, s_owner, s_name, s_ip = s
        keyboard.append([InlineKeyboardButton(f"🖥 {s_name} ({s_owner}) - {s_ip}", callback_data=f"server_{s_id}")])

    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text("🌐 **သိမ်းဆည်းထားသော Server အားလုံး၏ စာရင်း:**\n(Detail ကြည့်ရန် နှိပ်ပါ)", reply_markup=reply_markup, parse_mode="Markdown")

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    if not is_admin(query.from_user.id):
        await query.answer("⛔️ ခွင့်ပြုချက်မရှိပါ။", show_alert=True)
        return

    await query.answer()
    data = query.data

    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()

    if data.startswith("user_"):
        owner = data.replace("user_", "")
        cursor.execute("SELECT id, server_name, ip_address FROM servers WHERE owner_name = ?", (owner,))
        servers = cursor.fetchall()

        keyboard = []
        for s in servers:
            s_id, s_name, s_ip = s
            keyboard.append([InlineKeyboardButton(f"🖥 {s_name} ({s_ip})", callback_data=f"server_{s_id}")])
        
        keyboard.append([InlineKeyboardButton("🔙 Back to Users", callback_data="back_users")])
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(f"👤 **{owner}** ၏ Server များ ဖြစ်ပါသည်:\nကြည့်လိုသည့် Server ကို ရွေးပါ-", reply_markup=reply_markup, parse_mode="Markdown")

    elif data.startswith("server_"):
        s_id = int(data.replace("server_", ""))
        cursor.execute("SELECT * FROM servers WHERE id = ?", (s_id,))
        s = cursor.fetchone()

        if s:
            _, owner, name, ip, user, pwd, link, expire, remark = s
            remaining = get_remaining_days(expire)
            
            rem_str = f"⚠️ {remaining} days" if isinstance(remaining, int) and remaining <= 7 else f"{remaining} days"

            text = (
                f"🖥 **Server Details**\n\n"
                f"👤 **Owner:** {owner}\n"
                f"🏷 **Server Name:** `{name}`\n"
                f"🌐 **IP Address:** `{ip}`\n"
                f"👤 **Username:** `{user}`\n"
                f"🔑 **Password:** `{pwd}`\n"
                f"🔗 **Link:** {link}\n"
                f"📅 **Expire Date:** `{expire}`\n"
                f"⏳ **Remaining:** `{rem_str}`\n"
                f"📝 **Remark:** {remark}\n"
            )

            keyboard = [
                [InlineKeyboardButton("✏️ Edit Server", callback_data=f"editmenu_{s_id}"),
                 InlineKeyboardButton("🗑 Delete Server", callback_data=f"del_{s_id}")],
                [InlineKeyboardButton("🔙 Back", callback_data=f"user_{owner}")]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            await query.edit_message_text(text, reply_markup=reply_markup, parse_mode="Markdown")

    elif data.startswith("del_"):
        s_id = int(data.replace("del_", ""))
        cursor.execute("DELETE FROM servers WHERE id = ?", (s_id,))
        conn.commit()
        await query.edit_message_text("✅ **Server ကို အောင်မြင်စွာ ဖျက်ဆီးပြီးပါပြီ!**", parse_mode="Markdown")

    elif data.startswith("editmenu_"):
        s_id = int(data.replace("editmenu_", ""))
        keyboard = [
            [InlineKeyboardButton("Owner Name", callback_data=f"editfield_{s_id}_owner_name"),
             InlineKeyboardButton("Server Name", callback_data=f"editfield_{s_id}_server_name")],
            [InlineKeyboardButton("IP Address", callback_data=f"editfield_{s_id}_ip_address"),
             InlineKeyboardButton("Username", callback_data=f"editfield_{s_id}_username")],
            [InlineKeyboardButton("Password", callback_data=f"editfield_{s_id}_password"),
             InlineKeyboardButton("Server Link", callback_data=f"editfield_{s_id}_server_link")],
            [InlineKeyboardButton("Expire Date", callback_data=f"editfield_{s_id}_expire_date"),
             InlineKeyboardButton("Remark", callback_data=f"editfield_{s_id}_remark")],
            [InlineKeyboardButton("🔙 Cancel", callback_data=f"server_{s_id}")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text("✏️ **မည်သည့် အချက်အလက်ကို ပြင်ဆင်လိုပါသလဲ?**", reply_markup=reply_markup, parse_mode="Markdown")

    elif data == "back_users":
        conn.close()
        await list_users(query, context)
        return

    conn.close()

async def start_edit_field(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    parts = query.data.split("_", 2)
    s_id = int(parts[1])
    field = parts[2]

    context.user_data['edit_sid'] = s_id
    context.user_data['edit_field'] = field

    await query.edit_message_text(f"✏️ **{field.upper()}** အတွက် တန်ဖိုးအသစ်ကို ရိုက်ထည့်ပါ:")
    return WAIT_EDIT_VALUE

async def save_edit_value(update: Update, context: ContextTypes.DEFAULT_TYPE):
    new_val = update.message.text
    s_id = context.user_data.get('edit_sid')
    field = context.user_data.get('edit_field')

    if field == 'expire_date':
        try:
            datetime.strptime(new_val, "%Y-%m-%d")
        except ValueError:
            await update.message.reply_text("❌ ရက်စွဲပုံစံ မှားယွင်းနေပါသည်။ YYYY-MM-DD ပုံစံဖြင့် ပြန်ရိုက်ပါ:")
            return WAIT_EDIT_VALUE

    conn = sqlite3.connect("vps_tracker.db")
    cursor = conn.cursor()
    query_str = f"UPDATE servers SET {field} = ? WHERE id = ?"
    cursor.execute(query_str, (new_val, s_id))
    conn.commit()
    conn.close()

    await update.message.reply_text(f"✅ **{field}** ကို အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ!", parse_mode="Markdown")
    return ConversationHandler.END

async def handle_text_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    if text == "➕ Server အသစ်ထည့်ရန်":
        return await start_add(update, context)
    elif text == "👥 User အလိုက်ကြည့်ရန်":
        await list_users(update, context)
    elif text == "🌐 Server အားလုံးကြည့်ရန်":
        await list_all_servers(update, context)

def main():
    init_db()
    
    app = Application.builder().token(TOKEN).build()

    add_handler = ConversationHandler(
        entry_points=[
            CommandHandler("add", start_add),
            MessageHandler(filters.Regex("^➕ Server အသစ်ထည့်ရန်$"), start_add)
        ],
        states={
            WAIT_OWNER: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_owner)],
            WAIT_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_name)],
            WAIT_IP: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_ip)],
            WAIT_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_user)],
            WAIT_PASS: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_pass)],
            WAIT_LINK: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_link)],
            WAIT_EXPIRE: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_expire)],
            WAIT_REMARK: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_remark)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    edit_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(start_edit_field, pattern="^editfield_")],
        states={
            WAIT_EDIT_VALUE: [MessageHandler(filters.TEXT & ~filters.COMMAND, save_edit_value)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(add_handler)
    app.add_handler(edit_handler)
    app.add_handler(CommandHandler("user", list_users))
    app.add_handler(CommandHandler("all_servers", list_all_servers))
    
    app.add_handler(MessageHandler(filters.Regex("^(👥 User အလိုက်ကြည့်ရန်|🌐 Server အားလုံးကြည့်ရန်)$"), handle_text_menu))
    app.add_handler(CallbackQueryHandler(handle_callback))

    print("Bot is running...")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# ၄. ရိုက်ထည့်ထားသော Admin ID နှင့် Token များကို bot.py ထဲတွင် အစားထိုးခြင်း
sed -i "s/REPLACE_ADMIN_ID/$ADMIN_ID/" bot.py
sed -i "s/REPLACE_BOT_TOKEN/$BOT_TOKEN/" bot.py

echo "✅ bot.py အား အောင်မြင်စွာ ရေးသားပြီးပါပြီ!"

# ၅. PM2 ဖြင့် Background 24/7 Run ခြင်း
echo "🚀 PM2 ဖြင့် Telegram Bot ကို Background တွင် စတင် Run နေပါသည်..."
pm2 stop vps-bot 2>/dev/null || true
pm2 delete vps-bot 2>/dev/null || true
pm2 start ./venv/bin/python --name "vps-bot" -- bot.py

# Terminal ပိတ်သွားလည်း/VPS Reboot ဖြစ်သွားလည်း အလိုအလျောက် ပြန် run အောင် သိမ်းဆည်းခြင်း
pm2 save
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME 2>/dev/null || pm2 startup || true

echo ""
echo "=========================================="
echo "🎉 Installation အောင်မြင်စွာ ပြီးဆုံးပါပြီ!"
echo "🤖 Telegram Bot သို့သွားရောက်၍ /start ရိုက်ပြီး စတင်အသုံးပြုနိုင်ပါပြီ။"
echo "=========================================="
