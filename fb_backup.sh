#!/bin/bash
#
#  To make an incremental ("differential") backup we specify a backup level greater than "0".
#  An incremental backup of level "n" always contains the database mutations since the most recent level "n-1" backup.
#  Referência bibliográfica: https://www.firebirdsql.org/pdfmanual/html/nbackup-backups.html);
#
#    Nível do backup				Nome do arquivo de backup
#    0   - Backup completo (semanal)		backup-full-AAAAMMDD0000-00.nbk
#    1   - Backup incremental (diário)		backup-incr-AAAAMMDD0000-01.nbk
#    2:N - Backup incremental (a cada 2h)	backup-incr-AAAAMMDDHHMM-NN.nbk

	# O primeiro (e único) argumento deve ser o nome do arquivo de configuração.
	test $# -eq 1 && CONFIG=$1 || exit

	WORK_DIR=`pwd`
	BASENAME=`basename $0 | cut -d . -f 1`

	# Não iniciar uma nova instância caso já houver uma em execução;
	test -e /var/run/${BASENAME}.pid && ps -p `cat /var/run/${BASENAME}.pid` >/dev/null && exit 1
	echo $$ >/var/run/${BASENAME}.pid

	# Leia o arquivo de configuração, ou saia caso o mesmo não existir.
	source $WORK_DIR/$CONFIG 2>/dev/null || exit

	HM=`date +%H%M`
	DATE=`date +%m/%d/%Y`

	IONICE="false"

	INFO="[\e[36;1m INFO \e[m]"
	WARN="[\e[33;1m WARN \e[m]"

	status ()
	{

		PID=$!
		ERROR="false"

		test "$IONICE" = "true" && ionice -c 2 -n 7 -p $PID
		wait $PID

		if [ $? -ne 0 ]
		then

			ERROR="true"
			echo -e "\e[31;1m error\e[m"

			SUBJECT='Erro durante a execução de uma rotina de backup!'
			notification

		else

			echo -e "\e[92;1m ok\e[m"

		fi

	}

	notification ()
	{

		which s-nail >/dev/null && MAILD="s-nail" || MAILD="mailx"

		if which $MAILD >/dev/null
		then

			if [[ ! -z $NOTIF_SMTP && ! -z $NOTIF_TO && ! -z $NOTIF_FROM && ! -z $NOTIF_FROM_PASS ]]
			then

				export DEAD=/dev/null

				echo -ne "`date +"%d %b %Y %T"` - $INFO Enviando notificação p/ \"$NOTIF_TO\" via \"$NOTIF_SMTP\" (SMTP)..."

				$MAILD \
				-r "$NOTIF_FROM" \
				-s "$BASENAME: ${SUBJECT}" \
				-S smtp="$NOTIF_SMTP" \
				-S smtp-use-starttls \
				-S smtp-auth=login \
				-S smtp-auth-user="$NOTIF_FROM" \
				-S smtp-auth-password="$NOTIF_FROM_PASS" \
				-S ssl-verify=ignore \
				-S sendwait \
				$NOTIF_TO < /tmp/${BASENAME}_mail.log 2>${WORK_DIR}/mailx-notification-`date +%Y%m%d%H%M`.log

				if [ $? -eq 0 ]
				then

					echo -e "\e[92;1m ok\e[m"
					rm /tmp/${BASENAME}_mail.log

				else

					echo -e "\e[31;1m error\e[m"

				fi

			fi

		else

			echo -e "`date +"%d %b %Y %T"` - $WARN O envio de notificações requer a instalação do pacote \"heirloom-mailx\"."

		fi

	}

	manutencao ()
	{

		st_restore ()
		{

			if [ "$ERROR" == "false" ]
			then

				chgrp firebird $DIR_ORIGEM/.$DB_NAME
				chmod 660 $DIR_ORIGEM/.$DB_NAME

				echo -ne "`date +"%d %b %Y %T"` - $INFO Renomeando \"$DIR_ORIGEM/$DB_NAME\" p/ \"$DIR_ORIGEM/bkp-$DB_NAME\"..."
				IONICE="false"; mv $DIR_ORIGEM/$DB_NAME $DIR_ORIGEM/bkp-$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

				echo -ne "`date +"%d %b %Y %T"` - $INFO Renomeando \"$DIR_ORIGEM/.$DB_NAME\" p/ \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="false"; mv $DIR_ORIGEM/.$DB_NAME $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

				echo -ne "`date +"%d %b %Y %T"` - $INFO Removendo \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk\"..."
				IONICE="false"; rm $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk 2>>/tmp/${BASENAME}_mail.log & status

			else

				echo -ne "`date +"%d %b %Y %T"` - $INFO Reinicializando o banco de dados \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="false"; $FIREBIRD_BIN/gfix -online $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

			fi

		}

		echo -e "`date +"%d %b %Y %T"` - $INFO Iniciando a rotina de manutenção (backup/restore) do banco de dados \"$DIR_ORIGEM/$DB_NAME\"..."
		$IPTABLES_BIN -I INPUT 1 -p tcp --syn --dport 3050 -j REJECT

		n=1

		while [ $n -le $SHUTDOWN_LIFETIME ]
		do

			ERROR="false"

			echo -e "`date +"%d %b %Y %T"` - $INFO Aguardando \"shutdown\" do banco de dados \"$DIR_ORIGEM/$DB_NAME\" (tentativa \"$n\" de \"$SHUTDOWN_LIFETIME\")..."
			$FIREBIRD_BIN/gfix -shut single -tran 60 $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log || ERROR="true"

			if [ $ERROR = true ] && [ $n -eq 5 ]
			then

				echo -ne "`date +"%d %b %Y %T"` - $WARN Tentando \"shutdown\" forçado do banco de dados \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="false"; $FIREBIRD_BIN/gfix -shut single -force 0 $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

				break

			else

				test "$ERROR" = "false" && break || (( n++ ))

			fi

		done

		if [ "$ERROR" == "false" ]
		then

			test -d $DIR_DESTINO/$BASENAME/$BKP_NAME || mkdir -p $DIR_DESTINO/$BASENAME/$BKP_NAME 2>>/tmp/${BASENAME}_mail.log

			echo -ne "`date +"%d %b %Y %T"` - $INFO Executando backup do \"$DIR_ORIGEM/$DB_NAME\" p/ \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk\"..."
			IONICE="true"; $FIREBIRD_BIN/gbak -USER $DB_USER -PASSWORD $DB_PASSWORD -B $DIR_ORIGEM/$DB_NAME $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk 2>>/tmp/${BASENAME}_mail.log & status

			if [ "$ERROR" == "false" ]
			then

				if [ ! -z $DB_PAGE_SIZE ]
				then

					echo -ne "`date +"%d %b %Y %T"` - $INFO Restaurando \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk\" p/ \"$DIR_ORIGEM/.$DB_NAME\" (Page size: $DB_PAGE_SIZE)..."
					IONICE="true"; $FIREBIRD_BIN/gbak -USER $DB_USER -PASSWORD $DB_PASSWORD -C -P $DB_PAGE_SIZE $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk $DIR_ORIGEM/.$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status; st_restore

				else

					echo -ne "`date +"%d %b %Y %T"` - $INFO Restaurando \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk\" p/ \"$DIR_ORIGEM/.$DB_NAME\"..."
					IONICE="true"; $FIREBIRD_BIN/gbak -USER $DB_USER -PASSWORD $DB_PASSWORD -C $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_NAME}.fbk $DIR_ORIGEM/.$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status; st_restore

				fi

			else

				echo -ne "`date +"%d %b %Y %T"` - $INFO Reinicializando o banco de dados \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="false"; $FIREBIRD_BIN/gfix -online $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

			fi

		else

			echo -e "`date +"%d %b %Y %T"` - $WARN Falha no desligamento do banco de dados \"$DIR_ORIGEM/$DB_NAME\"! Abortando a rotina de manutenção.\n"

		fi

		$IPTABLES_BIN -D INPUT -p tcp --syn --dport 3050 -j REJECT
		echo -e "\r"

	}

	ext_backup ()
	{

		if [ -d $EXT_BACKUP ]
		then

			echo -ne "`date +"%d %b %Y %T"` - $INFO Copiando \"$EXT_BKP_FILE\" p/ \"$EXT_BACKUP\"..."
			IONICE="true"; cp $EXT_BKP_FILE $EXT_BACKUP 2>>/tmp/${BASENAME}_mail.log & status

		fi

	}

	# Verificar e notificar sobre a capacidade de armazenamento dos discos
	for FS in $DIR_ORIGEM $DIR_DESTINO $EXT_BACKUP
	do

		PERCENTUAL_USO=`df -h $FS | grep ^/dev/sd | awk '{print $5}' | sed 's/%//'`

		if [ $PERCENTUAL_USO -ge $LIMITE_USO_FS ]
		then

			df -h $FS >/tmp/${BASENAME}_mail.log
			echo -e "\n* Aviso gerado durante a execução do \"$0\" no host \"`hostname` em \"`date +%c`\"." >>/tmp/${BASENAME}_mail.log

			SUBJECT="*** ALERTA / CAPACIDADE DE ARMAZENAMENTO DO SISTEMA DE ARQUIVOS";	notification

		fi

	done

	# Compactação de arquivos de backup's dos dias anteriores
	for DB_NAME in $DATABASES
	do

		BKP_NAME=`echo $DB_NAME | cut -d "." -f 1`
		source $WORK_DIR/.$BASENAME/$BKP_NAME/tar.db 2>/dev/null

		if [ $? -eq 0 ] && [ "$DATE" != "$BKP_DATE" ] && [ -e "$WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst" ] && [ -d "$DIR_DESTINO/$BASENAME/$BKP_NAME" ]
		then

			ARQUIVO_TAR="${BKP_NAME}-incr-`date +%Y%m%d -d "$BKP_DATE"`"

			cd $DIR_DESTINO/$BASENAME/$BKP_NAME

			echo -ne "`date +"%d %b %Y %T"` - $INFO Compactando arquivos do \"$WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst\"..."
			IONICE="true"; tar -Jcf ${ARQUIVO_TAR}.tar.xz $(cat $WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst | grep ^"${BKP_NAME}-incr") 2>>/tmp/${BASENAME}_mail.log & status

			if [ "$ERROR" == "false" ]
			then

				FILE_SIZE=`du -hs ${ARQUIVO_TAR}.tar.xz | cut -f 1`
				echo -e "`date +"%d %b %Y %T"` - $INFO Arquivo: \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${ARQUIVO_TAR}.tar.xz\" ($FILE_SIZE)."

				while read BKP_FILE
				do

					echo -ne "`date +"%d %b %Y %T"` - $INFO Removendo \"$DIR_DESTINO/$BASENAME/$BKP_NAME/$BKP_FILE\"..."
					IONICE="false"; rm $BKP_FILE 2>>/tmp/${BASENAME}_mail.log & status

				done < <(cat $WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst | grep ^"${BKP_NAME}-incr")

				cp $WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst ${ARQUIVO_TAR}.lst
				rm $WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst

				test -n "$EXT_BACKUP" && EXT_BKP_FILE="$DIR_DESTINO/$BASENAME/$BKP_NAME/${ARQUIVO_TAR}.tar.xz"
				test -n "$EXT_BACKUP" && ext_backup

			elif [ -e ${ARQUIVO_TAR}.tar.xz ]
			then

				echo -ne "`date +"%d %b %Y %T"` - $INFO Removendo \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${ARQUIVO_TAR}.tar.xz\"..."
				IONICE="true"; rm ${ARQUIVO_TAR}.tar.xz 2>>/tmp/${BASENAME}_mail.log & status

			fi

			echo -e "\r"

		fi

	done

	if [ "$MANUTENCAO" == "true" ] && [ `date +%w` -eq $MANUTENCAO_DIA ]
	then

		for DB_NAME in $DATABASES
		do

			DATA_CRIACAO=`$FIREBIRD_BIN/gstat $DIR_ORIGEM/$DB_NAME -h | grep "Creation date" | awk '{print substr($0, index($0,$3))}'`
			DIAS_CRIACAO=$((($(date +%s)-$(date +%s --date "$DATA_CRIACAO"))/(3600*24)))

			if [ $DIAS_CRIACAO -ge $MANUTENCAO_DIAS ]
			then

				BKP_NAME=`echo $DB_NAME | cut -d "." -f 1`
				test -e $DIR_ORIGEM/$DB_NAME && manutencao || continue

			fi

		done

	fi

	for DB_NAME in $DATABASES
	do

		if [ ! -e $DIR_ORIGEM/$DB_NAME ]
		then

			echo -e "`date +"%d %b %Y %T"` - $WARN Arquivo \"$DIR_ORIGEM/$DB_NAME\" não encontrado!"

		else

			BKP_NAME=`echo $DB_NAME | cut -d "." -f 1`
			DATA_CRIACAO=`$FIREBIRD_BIN/gstat $DIR_ORIGEM/$DB_NAME -h | grep "Creation date" | awk '{print substr($0, index($0,$3))}'`

			BKP_FULL="${BKP_NAME}-full-`date +%Y%m%d -d "$DATA_CRIACAO"`"
			BKP_DAILY="${BKP_NAME}-incr-`date +%Y%m%d -d ${DATE}`0000-01"

			test -d $WORK_DIR/.$BASENAME/$BKP_NAME || mkdir -p $WORK_DIR/.$BASENAME/$BKP_NAME 2>>/tmp/${BASENAME}_mail.log
			test -d $DIR_DESTINO/$BASENAME/$BKP_NAME || mkdir $DIR_DESTINO/$BASENAME/$BKP_NAME 2>>/tmp/${BASENAME}_mail.log

			if [ ! -e $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.tar.xz ] && [ ! -e $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk ]
			then

				echo -ne "`date +"%d %b %Y %T"` - $INFO Executando backup completo de \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="true"; $FIREBIRD_BIN/nbackup -U $DB_USER -P $DB_PASSWORD -B 0 $DIR_ORIGEM/$DB_NAME $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk 2>>/tmp/${BASENAME}_mail.log & status

				if [ "$ERROR" = "true" ]
				then

					echo -ne "`date +"%d %b %Y %T"` - $INFO Removendo arquivo \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk\"..."
					rm -f $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk && echo -e "\e[92;1m ok\e[m" || echo -e "\e[31;1m error\e[m"

					echo -ne "`date +"%d %b %Y %T"` - $INFO Desbloqueando o banco de dados principal mesclando o arquivo delta (\"$DIR_ORIGEM/${DB_NAME}.delta\")..."
					$FIREBIRD_BIN/nbackup -N $DIR_ORIGEM/$DB_NAME && echo -e "\e[92;1m ok\e[m" || echo -e "\e[31;1m error\e[m"

					continue

				fi

				chmod 644 $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk

				FILE_SIZE=`du -hs $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk | cut -f 1`
				echo -e "`date +"%d %b %Y %T"` - $INFO Arquivo: \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk\" ($FILE_SIZE)."

				if [ "$BKP_FULL_COMPACTAR" == "true" ]
				then

					cd $DIR_DESTINO/$BASENAME/$BKP_NAME

					echo -ne "`date +"%d %b %Y %T"` - $INFO Compactando \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk\"..."
					IONICE="true"; tar -Jcf ${BKP_FULL}.tar.xz ${BKP_FULL}.nbk 2>>/tmp/${BASENAME}_mail.log &
					status; test "$ERROR" = "false" || continue

					FILE_SIZE=`du -hs ${BKP_FULL}.tar.xz | cut -f 1`
					echo -e "`date +"%d %b %Y %T"` - $INFO Arquivo: \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.tar.xz\" ($FILE_SIZE)."

					if [ "$BKP_FULL_MANTER" == "false" ]
					then

						echo -ne "`date +"%d %b %Y %T"` - $INFO Removendo \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk\"..."
						IONICE="true"; rm ${BKP_FULL}.nbk 2>>/tmp/${BASENAME}_mail.log & status

						test -n "$EXT_BACKUP" && EXT_BKP_FILE="$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.tar.xz"
						test -n "$EXT_BACKUP" && ext_backup

					fi

				else

					test -n "$EXT_BACKUP" && EXT_BKP_FILE="$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_FULL}.nbk"
					test -n "$EXT_BACKUP" && ext_backup

				fi

			elif [ ! -e "$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_DAILY}.nbk" ]
			then

				# Database Housekeeping And Garbage Collection
				DATA_CRIACAO=`$FIREBIRD_BIN/gstat $DIR_ORIGEM/$DB_NAME -h | grep "Creation date" | awk '{print substr($0, index($0,$3))}' | xargs -I {} date +%m/%d/%Y -d "{}"`

				if [ "$SWEEP" == "true" ] && [ "$DATA_CRIACAO" != "$DATE" ]
				then

					echo -ne "`date +"%d %b %Y %T"` - $INFO Executando varredura e coleta de lixo (sweep) do \"$DIR_ORIGEM/$DB_NAME\"..."
					IONICE="true"; $FIREBIRD_BIN/gfix -sweep $DIR_ORIGEM/$DB_NAME 2>>/tmp/${BASENAME}_mail.log & status

					echo -e "\r"

				fi

				echo -ne "`date +"%d %b %Y %T"` - $INFO Executando backup incremental (daily) de \"$DIR_ORIGEM/$DB_NAME\"..."
				IONICE="true"; $FIREBIRD_BIN/nbackup -U $DB_USER -P $DB_PASSWORD -B 1 $DIR_ORIGEM/$DB_NAME $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_DAILY}.nbk 2>>/tmp/${BASENAME}_mail.log &
				status; test "$ERROR" = "false" || continue

				chmod 644 $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_DAILY}.nbk

				FILE_SIZE=`du -hs $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_DAILY}.nbk | cut -f 1`
				echo -e "`date +"%d %b %Y %T"` - $INFO Arquivo: \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_DAILY}.nbk\" ($FILE_SIZE)."

				echo "BKP_DATE=$DATE" >$WORK_DIR/.$BASENAME/$BKP_NAME/tar.db
				echo "BKP_LEVEL=1" >$WORK_DIR/.$BASENAME/$BKP_NAME/nbackup.db
				echo -e "${BKP_FULL}.nbk\n${BKP_DAILY}.nbk" >$WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst

			else

				echo -ne "`date +"%d %b %Y %T"` - $INFO Executando backup incremental de \"$DIR_ORIGEM/$DB_NAME\"..."
				source $WORK_DIR/.$BASENAME/$BKP_NAME/nbackup.db 2>>/tmp/${BASENAME}_mail.log

				if [ $? -eq 0 ]
				then

					(( BKP_LEVEL++ )); BKP_HOURLY="${BKP_NAME}-incr-`date +%Y%m%d -d ${DATE}`${HM}-`printf "%02d" $BKP_LEVEL`"

					IONICE="true"; $FIREBIRD_BIN/nbackup -U $DB_USER -P $DB_PASSWORD -B $BKP_LEVEL $DIR_ORIGEM/$DB_NAME $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_HOURLY}.nbk 2>>/tmp/${BASENAME}_mail.log &
					status; test "$ERROR" = "false" || continue

					chmod 644 $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_HOURLY}.nbk

					FILE_SIZE=`du -hs $DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_HOURLY}.nbk | cut -f 1`
					echo -e "`date +"%d %b %Y %T"` - $INFO Arquivo: \"$DIR_DESTINO/$BASENAME/$BKP_NAME/${BKP_HOURLY}.nbk\" ($FILE_SIZE)."

					echo "${BKP_HOURLY}.nbk" >>$WORK_DIR/.$BASENAME/$BKP_NAME/tar.lst
					echo "BKP_LEVEL=$BKP_LEVEL" >$WORK_DIR/.$BASENAME/$BKP_NAME/nbackup.db

				else

					echo -e "\e[31;1m error\e[m"

					SUBJECT='Erro durante a execução de uma rotina de backup!'
					notification

				fi

			fi

		fi

		echo -e "\r"

	done
